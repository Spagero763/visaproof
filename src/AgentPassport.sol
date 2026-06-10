// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @notice Minimal view of the ERC 8004 Identity Registry on Celo.
/// @dev The registry mints an ERC 721 identity NFT per agent. Ownership of the
///      token id is what authorises a caller to manage that agent's passport.
interface IIdentityRegistry {
    function ownerOf(uint256 agentId) external view returns (address);
}

/// @notice Activity score source consumed when recomputing an agent's tier.
/// @dev Implemented by AgentActivityOracle. Kept as an interface so the
///      passport stays decoupled from the verification engine.
interface IActivityOracle {
    function getActivityScore(uint256 agentId)
        external
        view
        returns (uint256 totalVolumeCUSD, uint256 txCount, uint256 lastUpdated);
}

/// @notice Minimal view of the Self Agent ID registry on Celo
///         (`0xaC3DF9ABf80d0F5c020C06B04Cced27763355944`, symbol "SAID").
/// @dev The registry is a soulbound ERC 721 that binds an agent identity to a
///      Self Protocol proof of human. VisaProof reads it to gate passports on
///      verified human control:
///        - `ownerOf` proves the caller controls the Self Agent ID,
///        - `hasHumanProof` / `isProofFresh` prove a live human verification,
///        - `getHumanNullifier` is the per human Sybil resistance identifier.
///      Self performs all zero knowledge verification; VisaProof only consumes
///      the result, so no proof plumbing lives in this contract.
interface ISelfAgentRegistry {
    function ownerOf(uint256 selfAgentId) external view returns (address);
    function hasHumanProof(uint256 selfAgentId) external view returns (bool);
    function isProofFresh(uint256 selfAgentId) external view returns (bool);
    function getHumanNullifier(uint256 selfAgentId) external view returns (uint256);
}

/// @title AgentPassport
/// @notice Core identity tracker for VisaProof. Maps each ERC 8004 agent id to
///         its Agent Visa tier and a passport record, recomputing the tier from
///         verified on chain activity.
contract AgentPassport {
    // ---------------------------------------------------------------------
    // Types
    // ---------------------------------------------------------------------

    enum Tier {
        Tourist,
        WorkVisa,
        Citizenship
    }

    struct Passport {
        bool registered;
        Tier tier;
        uint256 volumeCUSD;
        uint256 txCount;
        uint256 updatedAt;
        // Self Agent ID bound at registration: the human-verified identity that
        // controls this passport, and its per-human nullifier (Sybil anchor).
        uint256 selfAgentId;
        uint256 humanNullifier;
    }

    // ---------------------------------------------------------------------
    // Tier thresholds (v1 protocol parameters)
    // ---------------------------------------------------------------------

    /// @notice Tx count at or above this bound qualifies for Work Visa.
    /// @dev Per the Celo Agent Visa program: 1,000 transactions OR $5,000 volume.
    uint256 public constant WORK_VISA_TX_COUNT = 1_000;
    /// @notice Volume in cUSD (18 decimals) qualifying for Work Visa.
    uint256 public constant WORK_VISA_VOLUME_CUSD = 5_000e18;

    /// @notice Tx count qualifying for Citizenship.
    uint256 public constant CITIZENSHIP_TX_COUNT = 10_000;
    /// @notice Volume in cUSD (18 decimals) qualifying for Citizenship.
    uint256 public constant CITIZENSHIP_VOLUME_CUSD = 15_000e18;

    // ---------------------------------------------------------------------
    // Storage
    // ---------------------------------------------------------------------

    /// @notice ERC 8004 Identity Registry used to authorise agent controllers.
    IIdentityRegistry public immutable identityRegistry;

    /// @notice Activity oracle supplying verified volume and tx counts.
    IActivityOracle public immutable activityOracle;

    /// @notice Self Agent ID registry used to gate passports on proof of human.
    ISelfAgentRegistry public immutable selfAgentRegistry;

    mapping(uint256 agentId => Passport) private _passports;

    // ---------------------------------------------------------------------
    // Events
    // ---------------------------------------------------------------------

    event AgentRegistered(
        uint256 indexed agentId, address indexed controller, uint256 selfAgentId, uint256 humanNullifier
    );
    event TierUpgraded(uint256 indexed agentId, Tier oldTier, Tier newTier, uint256 volumeCUSD, uint256 txCount);

    // ---------------------------------------------------------------------
    // Errors
    // ---------------------------------------------------------------------

    error ZeroAddress();
    error NotAgentOwner(uint256 agentId, address caller);
    error AlreadyRegistered(uint256 agentId);
    error NotRegistered(uint256 agentId);
    error NoUpgradeAvailable(uint256 agentId, Tier currentTier);
    error NotHumanController(uint256 selfAgentId, address caller);
    error HumanProofMissing(uint256 selfAgentId);
    error HumanProofStale(uint256 selfAgentId);

    // ---------------------------------------------------------------------
    // Constructor
    // ---------------------------------------------------------------------

    constructor(address identityRegistry_, address activityOracle_, address selfAgentRegistry_) {
        if (identityRegistry_ == address(0) || activityOracle_ == address(0) || selfAgentRegistry_ == address(0)) {
            revert ZeroAddress();
        }
        identityRegistry = IIdentityRegistry(identityRegistry_);
        activityOracle = IActivityOracle(activityOracle_);
        selfAgentRegistry = ISelfAgentRegistry(selfAgentRegistry_);
    }

    // ---------------------------------------------------------------------
    // Mutating functions
    // ---------------------------------------------------------------------

    /// @notice Link an ERC 8004 agent id to VisaProof, creating its passport.
    /// @param agentId      ERC 8004 agent id. Caller must own its identity NFT.
    /// @param selfAgentId  Self Agent ID held by the caller, carrying a fresh
    ///                     Self Protocol proof of human.
    /// @dev Sybil resistance: the passport is bound to the Self Agent ID's human
    ///      nullifier, so every VisaProof identity traces back to a verified
    ///      human. The caller must control both identities — the ERC 8004 agent
    ///      NFT and the Self Agent ID — and the human proof must be live.
    function registerAgent(uint256 agentId, uint256 selfAgentId) external {
        _requireAgentOwner(agentId);
        if (_passports[agentId].registered) revert AlreadyRegistered(agentId);

        uint256 nullifier = _requireFreshHuman(selfAgentId);

        _passports[agentId] = Passport({
            registered: true,
            tier: Tier.Tourist,
            volumeCUSD: 0,
            txCount: 0,
            updatedAt: block.timestamp,
            selfAgentId: selfAgentId,
            humanNullifier: nullifier
        });

        emit AgentRegistered(agentId, msg.sender, selfAgentId, nullifier);
    }

    /// @notice Recompute an agent's tier from verified oracle activity.
    /// @dev Reverts when the recomputed tier is not higher than the current one,
    ///      so the call only succeeds on a genuine upgrade.
    function upgradeTier(uint256 agentId) external {
        Passport storage p = _passports[agentId];
        if (!p.registered) revert NotRegistered(agentId);

        (uint256 volumeCUSD, uint256 txCount,) = activityOracle.getActivityScore(agentId);
        Tier newTier = _computeTier(volumeCUSD, txCount);

        if (uint8(newTier) <= uint8(p.tier)) {
            revert NoUpgradeAvailable(agentId, p.tier);
        }

        Tier oldTier = p.tier;
        p.tier = newTier;
        p.volumeCUSD = volumeCUSD;
        p.txCount = txCount;
        p.updatedAt = block.timestamp;

        emit TierUpgraded(agentId, oldTier, newTier, volumeCUSD, txCount);
    }

    // ---------------------------------------------------------------------
    // View functions
    // ---------------------------------------------------------------------

    /// @notice Current Visa tier for an agent.
    function getTier(uint256 agentId) external view returns (Tier) {
        if (!_passports[agentId].registered) revert NotRegistered(agentId);
        return _passports[agentId].tier;
    }

    /// @notice Full passport record for an agent.
    function getPassport(uint256 agentId) external view returns (Passport memory) {
        if (!_passports[agentId].registered) revert NotRegistered(agentId);
        return _passports[agentId];
    }

    /// @notice Whether an agent has registered a passport.
    function isRegistered(uint256 agentId) external view returns (bool) {
        return _passports[agentId].registered;
    }

    /// @notice Live proof-of-human status for a registered agent.
    /// @return selfAgentId The Self Agent ID bound at registration.
    /// @return nullifier   The per-human nullifier recorded at registration.
    /// @return human       Whether that Self Agent ID still carries a fresh
    ///                     human proof right now (proofs expire and can be
    ///                     revoked, so this is re-read from the Self registry).
    function humanProof(uint256 agentId)
        external
        view
        returns (uint256 selfAgentId, uint256 nullifier, bool human)
    {
        Passport storage p = _passports[agentId];
        if (!p.registered) revert NotRegistered(agentId);
        selfAgentId = p.selfAgentId;
        nullifier = p.humanNullifier;
        human = selfAgentRegistry.hasHumanProof(selfAgentId) && selfAgentRegistry.isProofFresh(selfAgentId);
    }

    /// @notice Tier an agent would hold given a volume and tx count, without state changes.
    function previewTier(uint256 volumeCUSD, uint256 txCount) external pure returns (Tier) {
        return _computeTier(volumeCUSD, txCount);
    }

    // ---------------------------------------------------------------------
    // Internal
    // ---------------------------------------------------------------------

    function _requireAgentOwner(uint256 agentId) private view {
        if (identityRegistry.ownerOf(agentId) != msg.sender) {
            revert NotAgentOwner(agentId, msg.sender);
        }
    }

    /// @dev Verify the caller controls `selfAgentId` and it carries a fresh
    ///      proof of human, then return its nullifier. All zero knowledge
    ///      verification was performed by Self; this only reads the result.
    function _requireFreshHuman(uint256 selfAgentId) private view returns (uint256) {
        if (selfAgentRegistry.ownerOf(selfAgentId) != msg.sender) {
            revert NotHumanController(selfAgentId, msg.sender);
        }
        if (!selfAgentRegistry.hasHumanProof(selfAgentId)) {
            revert HumanProofMissing(selfAgentId);
        }
        if (!selfAgentRegistry.isProofFresh(selfAgentId)) {
            revert HumanProofStale(selfAgentId);
        }
        return selfAgentRegistry.getHumanNullifier(selfAgentId);
    }

    /// @dev Tier ladder: either threshold (tx count OR volume) lifts the tier.
    function _computeTier(uint256 volumeCUSD, uint256 txCount) private pure returns (Tier) {
        if (txCount >= CITIZENSHIP_TX_COUNT || volumeCUSD >= CITIZENSHIP_VOLUME_CUSD) {
            return Tier.Citizenship;
        }
        if (txCount >= WORK_VISA_TX_COUNT || volumeCUSD >= WORK_VISA_VOLUME_CUSD) {
            return Tier.WorkVisa;
        }
        return Tier.Tourist;
    }
}
