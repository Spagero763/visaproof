// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {AgentPassport, IIdentityRegistry, IActivityOracle} from "./AgentPassport.sol";

/// @title AgentVisaRegistry
/// @notice Coordination layer for VisaProof. Tracks Agent Visa applications,
///         provides a tier filtered leaderboard sorted by verified cUSD volume,
///         and indexes registered skills so other agents can discover high tier
///         counterparts. Skill keywords mirror the agent's ERC 8004 metadata
///         (the OASF services/skills entries); writes are gated by identity
///         ownership so the index cannot drift from the canonical metadata.
contract AgentVisaRegistry {
    // ---------------------------------------------------------------------
    // Storage
    // ---------------------------------------------------------------------

    /// @notice Passport contract supplying tier, cached volume and tx count.
    AgentPassport public immutable passport;

    /// @notice ERC 8004 Identity Registry used to authorise agent controllers.
    IIdentityRegistry public immutable identityRegistry;

    /// @notice Activity oracle used for live eligibility checks.
    IActivityOracle public immutable activityOracle;

    /// @notice Applicants in registration order.
    uint256[] private _applicants;
    mapping(uint256 agentId => bool) public hasApplied;

    /// @notice Capability keywords declared per agent (case sensitive).
    mapping(uint256 agentId => string[]) private _capabilities;
    mapping(uint256 agentId => mapping(bytes32 capHash => bool)) private _hasCapability;

    /// @notice Reverse index: capability hash to applicant ids.
    mapping(bytes32 capHash => uint256[]) private _agentsByCapability;
    mapping(bytes32 capHash => mapping(uint256 agentId => uint256)) private _capabilityIndex;

    // ---------------------------------------------------------------------
    // Events
    // ---------------------------------------------------------------------

    event VisaApplied(uint256 indexed agentId, address indexed controller);
    event CapabilityAdded(uint256 indexed agentId, bytes32 indexed capabilityHash, string capability);
    event CapabilityRemoved(uint256 indexed agentId, bytes32 indexed capabilityHash, string capability);

    // ---------------------------------------------------------------------
    // Errors
    // ---------------------------------------------------------------------

    error ZeroAddress();
    error NotAgentOwner(uint256 agentId, address caller);
    error PassportNotRegistered(uint256 agentId);
    error AlreadyApplied(uint256 agentId);
    error NotApplied(uint256 agentId);
    error EmptyCapability();
    error CapabilityAlreadySet(uint256 agentId, string capability);
    error CapabilityNotSet(uint256 agentId, string capability);

    // ---------------------------------------------------------------------
    // Constructor
    // ---------------------------------------------------------------------

    constructor(address passport_, address identityRegistry_, address activityOracle_) {
        if (passport_ == address(0) || identityRegistry_ == address(0) || activityOracle_ == address(0)) {
            revert ZeroAddress();
        }
        passport = AgentPassport(passport_);
        identityRegistry = IIdentityRegistry(identityRegistry_);
        activityOracle = IActivityOracle(activityOracle_);
    }

    // ---------------------------------------------------------------------
    // Applications
    // ---------------------------------------------------------------------

    /// @notice Submit an agent for Visa consideration.
    /// @dev Agent must already hold a VisaProof passport. Caller must own
    ///      the agent's ERC 8004 identity NFT.
    function applyForVisa(uint256 agentId) external {
        _requireAgentOwner(agentId);
        if (!passport.isRegistered(agentId)) revert PassportNotRegistered(agentId);
        if (hasApplied[agentId]) revert AlreadyApplied(agentId);

        hasApplied[agentId] = true;
        _applicants.push(agentId);

        emit VisaApplied(agentId, msg.sender);
    }

    // ---------------------------------------------------------------------
    // Capabilities (index mirrors the ERC 8004 IPFS metadata)
    // ---------------------------------------------------------------------

    /// @notice Add a capability keyword to an agent's discovery index.
    function setCapability(uint256 agentId, string calldata capability) external {
        _requireAgentOwner(agentId);
        if (!hasApplied[agentId]) revert NotApplied(agentId);
        if (bytes(capability).length == 0) revert EmptyCapability();

        bytes32 capHash = keccak256(bytes(capability));
        if (_hasCapability[agentId][capHash]) revert CapabilityAlreadySet(agentId, capability);

        _hasCapability[agentId][capHash] = true;
        _capabilities[agentId].push(capability);

        uint256[] storage list = _agentsByCapability[capHash];
        _capabilityIndex[capHash][agentId] = list.length;
        list.push(agentId);

        emit CapabilityAdded(agentId, capHash, capability);
    }

    /// @notice Remove a previously declared capability from an agent.
    function removeCapability(uint256 agentId, string calldata capability) external {
        _requireAgentOwner(agentId);

        bytes32 capHash = keccak256(bytes(capability));
        if (!_hasCapability[agentId][capHash]) revert CapabilityNotSet(agentId, capability);

        _hasCapability[agentId][capHash] = false;
        _removeFromStringArray(_capabilities[agentId], capability);
        _removeAgentFromCapabilityList(capHash, agentId);

        emit CapabilityRemoved(agentId, capHash, capability);
    }

    // ---------------------------------------------------------------------
    // Views
    // ---------------------------------------------------------------------

    /// @notice Whether an agent's live oracle score qualifies for a tier.
    function isEligible(uint256 agentId, AgentPassport.Tier tier) external view returns (bool) {
        (uint256 volumeCUSD, uint256 txCount,) = activityOracle.getActivityScore(agentId);
        AgentPassport.Tier reachable = passport.previewTier(volumeCUSD, txCount);
        return uint8(reachable) >= uint8(tier);
    }

    /// @notice Applicants whose passport tier is at or above `minTier`,
    ///         sorted by cached volume descending and truncated to `limit`.
    /// @dev O(n^2) by design. Suitable for the v1 applicant set; off chain
    ///      indexers should be used once the registry grows past a few
    ///      hundred entries.
    function getLeaderboard(uint8 minTier, uint256 limit) external view returns (uint256[] memory) {
        uint256 n = _applicants.length;
        if (n == 0 || limit == 0) return new uint256[](0);

        uint256[] memory ids = new uint256[](n);
        uint256[] memory volumes = new uint256[](n);
        uint256 m;

        for (uint256 i; i < n; ++i) {
            uint256 agentId = _applicants[i];
            AgentPassport.Passport memory p = passport.getPassport(agentId);
            if (uint8(p.tier) >= minTier) {
                ids[m] = agentId;
                volumes[m] = p.volumeCUSD;
                ++m;
            }
        }

        if (m == 0) return new uint256[](0);
        uint256 outLen = m < limit ? m : limit;

        // Partial selection sort: surface the top outLen entries by volume.
        for (uint256 i; i < outLen; ++i) {
            uint256 maxIdx = i;
            for (uint256 j = i + 1; j < m; ++j) {
                if (volumes[j] > volumes[maxIdx]) maxIdx = j;
            }
            if (maxIdx != i) {
                (volumes[i], volumes[maxIdx]) = (volumes[maxIdx], volumes[i]);
                (ids[i], ids[maxIdx]) = (ids[maxIdx], ids[i]);
            }
        }

        uint256[] memory result = new uint256[](outLen);
        for (uint256 i; i < outLen; ++i) {
            result[i] = ids[i];
        }
        return result;
    }

    /// @notice Agents indexed under a capability keyword (case sensitive).
    function getAgentsByCapability(string calldata capability) external view returns (uint256[] memory) {
        return _agentsByCapability[keccak256(bytes(capability))];
    }

    /// @notice Capability list declared by an agent.
    function capabilitiesOf(uint256 agentId) external view returns (string[] memory) {
        return _capabilities[agentId];
    }

    /// @notice Number of submitted applications.
    function applicantsCount() external view returns (uint256) {
        return _applicants.length;
    }

    /// @notice Full applicant list in registration order.
    function applicants() external view returns (uint256[] memory) {
        return _applicants;
    }

    // ---------------------------------------------------------------------
    // Internal
    // ---------------------------------------------------------------------

    function _requireAgentOwner(uint256 agentId) private view {
        if (identityRegistry.ownerOf(agentId) != msg.sender) {
            revert NotAgentOwner(agentId, msg.sender);
        }
    }

    function _removeFromStringArray(string[] storage arr, string calldata value) private {
        bytes32 target = keccak256(bytes(value));
        uint256 len = arr.length;
        for (uint256 i; i < len; ++i) {
            if (keccak256(bytes(arr[i])) == target) {
                arr[i] = arr[len - 1];
                arr.pop();
                return;
            }
        }
    }

    function _removeAgentFromCapabilityList(bytes32 capHash, uint256 agentId) private {
        uint256[] storage list = _agentsByCapability[capHash];
        uint256 idx = _capabilityIndex[capHash][agentId];
        uint256 last = list.length - 1;
        if (idx != last) {
            uint256 movedId = list[last];
            list[idx] = movedId;
            _capabilityIndex[capHash][movedId] = idx;
        }
        list.pop();
        delete _capabilityIndex[capHash][agentId];
    }
}
