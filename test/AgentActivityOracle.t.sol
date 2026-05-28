// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {AgentActivityOracle, IIdentityRegistry, IPriceOracle} from "../src/AgentActivityOracle.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @dev Mock ERC 8004 identity registry. Maps agent id to its controller.
contract MockIdentityRegistry is IIdentityRegistry {
    mapping(uint256 => address) public owners;

    function setOwner(uint256 agentId, address owner) external {
        owners[agentId] = owner;
    }

    function ownerOf(uint256 agentId) external view returns (address) {
        return owners[agentId];
    }
}

/// @dev Mock price oracle with per token cUSD rates (rate scaled by 1e18 per token unit).
contract MockPriceOracle is IPriceOracle {
    mapping(address => uint256) public rate; // cUSD per 1e18 token units

    function setRate(address token, uint256 r) external {
        rate[token] = r;
    }

    function toCUSD(address token, uint256 amount) external view returns (uint256) {
        return (amount * rate[token]) / 1e18;
    }
}

contract AgentActivityOracleTest is Test {
    AgentActivityOracle internal oracle;
    MockIdentityRegistry internal registry;
    MockPriceOracle internal prices;

    address internal owner = makeAddr("owner");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    address internal cUSD = makeAddr("cUSD");
    address internal cEUR = makeAddr("cEUR");
    address internal usdt = makeAddr("usdt");

    uint256 internal constant AGENT_ID = 1234;

    event TokenSupported(address indexed token, bool supported);
    event PriceOracleUpdated(address indexed oracle);
    event ActivitySubmitted(
        uint256 indexed agentId, address indexed submitter, uint256 newTxCount, uint256 addedVolumeCUSD
    );

    function setUp() public {
        registry = new MockIdentityRegistry();
        prices = new MockPriceOracle();
        oracle = new AgentActivityOracle(address(registry), address(prices), owner);

        registry.setOwner(AGENT_ID, alice);

        // 1:1 for cUSD and USDT, 1.1 cUSD per cEUR.
        prices.setRate(cUSD, 1e18);
        prices.setRate(usdt, 1e18);
        prices.setRate(cEUR, 1.1e18);

        vm.startPrank(owner);
        oracle.setSupportedToken(cUSD, true);
        oracle.setSupportedToken(cEUR, true);
        oracle.setSupportedToken(usdt, true);
        vm.stopPrank();
    }

    // -----------------------------------------------------------------
    // Constructor
    // -----------------------------------------------------------------

    function test_Constructor_RevertsOnZeroRegistry() public {
        vm.expectRevert(AgentActivityOracle.ZeroAddress.selector);
        new AgentActivityOracle(address(0), address(prices), owner);
    }

    function test_Constructor_RevertsOnZeroPriceOracle() public {
        vm.expectRevert(AgentActivityOracle.ZeroAddress.selector);
        new AgentActivityOracle(address(registry), address(0), owner);
    }

    function test_Constructor_SetsState() public view {
        assertEq(address(oracle.identityRegistry()), address(registry));
        assertEq(address(oracle.priceOracle()), address(prices));
        assertEq(oracle.owner(), owner);
    }

    // -----------------------------------------------------------------
    // Admin: setSupportedToken
    // -----------------------------------------------------------------

    function test_SetSupportedToken_AddsAndEnumerates() public {
        address[] memory list = oracle.supportedTokens();
        assertEq(list.length, 3);
        assertTrue(oracle.supportedToken(cUSD));
    }

    function test_SetSupportedToken_RevertsOnZero() public {
        vm.prank(owner);
        vm.expectRevert(AgentActivityOracle.ZeroAddress.selector);
        oracle.setSupportedToken(address(0), true);
    }

    function test_SetSupportedToken_OnlyOwner() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        oracle.setSupportedToken(cUSD, true);
    }

    function test_SetSupportedToken_RemoveShrinksList() public {
        vm.prank(owner);
        oracle.setSupportedToken(cEUR, false);

        assertFalse(oracle.supportedToken(cEUR));
        address[] memory list = oracle.supportedTokens();
        assertEq(list.length, 2);
        for (uint256 i; i < list.length; ++i) {
            assertTrue(list[i] != cEUR);
        }
    }

    function test_SetSupportedToken_IdempotentAddNoDuplicate() public {
        vm.prank(owner);
        oracle.setSupportedToken(cUSD, true); // already supported
        assertEq(oracle.supportedTokens().length, 3);
    }

    function test_SetSupportedToken_IdempotentRemoveUnknown() public {
        address random = makeAddr("random");
        vm.prank(owner);
        oracle.setSupportedToken(random, false); // not supported, no-op
        assertEq(oracle.supportedTokens().length, 3);
    }

    // -----------------------------------------------------------------
    // Admin: setPriceOracle
    // -----------------------------------------------------------------

    function test_SetPriceOracle_Updates() public {
        MockPriceOracle next = new MockPriceOracle();
        vm.prank(owner);
        vm.expectEmit(true, false, false, false);
        emit PriceOracleUpdated(address(next));
        oracle.setPriceOracle(address(next));
        assertEq(address(oracle.priceOracle()), address(next));
    }

    function test_SetPriceOracle_RevertsOnZero() public {
        vm.prank(owner);
        vm.expectRevert(AgentActivityOracle.ZeroAddress.selector);
        oracle.setPriceOracle(address(0));
    }

    function test_SetPriceOracle_OnlyOwner() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        oracle.setPriceOracle(address(prices));
    }

    // -----------------------------------------------------------------
    // submitActivity
    // -----------------------------------------------------------------

    function test_SubmitActivity_SingleToken() public {
        (bytes32[] memory h, uint256[] memory a, address[] memory t) = _one(keccak256("tx1"), 500e18, cUSD);

        vm.expectEmit(true, true, false, true);
        emit ActivitySubmitted(AGENT_ID, alice, 1, 500e18);

        vm.prank(alice);
        oracle.submitActivity(AGENT_ID, h, a, t);

        (uint256 vol, uint256 txCount, uint256 updated) = oracle.getActivityScore(AGENT_ID);
        assertEq(vol, 500e18);
        assertEq(txCount, 1);
        assertEq(updated, block.timestamp);
        assertEq(oracle.aggregateVolume(AGENT_ID), 500e18);
    }

    function test_SubmitActivity_MultiTokenAggregatesToCUSD() public {
        bytes32[] memory h = new bytes32[](3);
        uint256[] memory a = new uint256[](3);
        address[] memory t = new address[](3);
        h[0] = keccak256("a");
        a[0] = 100e18;
        t[0] = cUSD; // 100
        h[1] = keccak256("b");
        a[1] = 100e18;
        t[1] = cEUR; // 110
        h[2] = keccak256("c");
        a[2] = 100e18;
        t[2] = usdt; // 100

        vm.prank(alice);
        oracle.submitActivity(AGENT_ID, h, a, t);

        assertEq(oracle.aggregateVolume(AGENT_ID), 310e18);
        (, uint256 txCount,) = oracle.getActivityScore(AGENT_ID);
        assertEq(txCount, 3);

        address[] memory vt = oracle.verifiedTokens(AGENT_ID);
        assertEq(vt.length, 3);
    }

    function test_SubmitActivity_AccumulatesAcrossCalls() public {
        (bytes32[] memory h1, uint256[] memory a1, address[] memory t1) = _one(keccak256("x1"), 200e18, cUSD);
        vm.prank(alice);
        oracle.submitActivity(AGENT_ID, h1, a1, t1);

        (bytes32[] memory h2, uint256[] memory a2, address[] memory t2) = _one(keccak256("x2"), 300e18, cUSD);
        vm.prank(alice);
        oracle.submitActivity(AGENT_ID, h2, a2, t2);

        (uint256 vol, uint256 txCount,) = oracle.getActivityScore(AGENT_ID);
        assertEq(vol, 500e18);
        assertEq(txCount, 2);

        // Same token across calls is recorded once in verifiedTokens.
        assertEq(oracle.verifiedTokens(AGENT_ID).length, 1);
    }

    function test_SubmitActivity_RevertsWhenNotAgentOwner() public {
        (bytes32[] memory h, uint256[] memory a, address[] memory t) = _one(keccak256("tx1"), 1e18, cUSD);
        vm.expectRevert(abi.encodeWithSelector(AgentActivityOracle.NotAgentOwner.selector, AGENT_ID, bob));
        vm.prank(bob);
        oracle.submitActivity(AGENT_ID, h, a, t);
    }

    function test_SubmitActivity_RevertsOnEmpty() public {
        bytes32[] memory h = new bytes32[](0);
        uint256[] memory a = new uint256[](0);
        address[] memory t = new address[](0);
        vm.prank(alice);
        vm.expectRevert(AgentActivityOracle.EmptySubmission.selector);
        oracle.submitActivity(AGENT_ID, h, a, t);
    }

    function test_SubmitActivity_RevertsOnLengthMismatch() public {
        bytes32[] memory h = new bytes32[](2);
        uint256[] memory a = new uint256[](1);
        address[] memory t = new address[](2);
        h[0] = keccak256("a");
        h[1] = keccak256("b");
        a[0] = 1e18;
        t[0] = cUSD;
        t[1] = cUSD;
        vm.prank(alice);
        vm.expectRevert(AgentActivityOracle.LengthMismatch.selector);
        oracle.submitActivity(AGENT_ID, h, a, t);
    }

    function test_SubmitActivity_RevertsOnZeroTxHash() public {
        (bytes32[] memory h, uint256[] memory a, address[] memory t) = _one(bytes32(0), 1e18, cUSD);
        vm.prank(alice);
        vm.expectRevert(AgentActivityOracle.ZeroTxHash.selector);
        oracle.submitActivity(AGENT_ID, h, a, t);
    }

    function test_SubmitActivity_RevertsOnUnsupportedToken() public {
        address random = makeAddr("random");
        (bytes32[] memory h, uint256[] memory a, address[] memory t) = _one(keccak256("tx1"), 1e18, random);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(AgentActivityOracle.UnsupportedToken.selector, random));
        oracle.submitActivity(AGENT_ID, h, a, t);
    }

    function test_SubmitActivity_RevertsOnDuplicateWithinCall() public {
        bytes32 dup = keccak256("dup");
        bytes32[] memory h = new bytes32[](2);
        uint256[] memory a = new uint256[](2);
        address[] memory t = new address[](2);
        h[0] = dup;
        h[1] = dup;
        a[0] = 1e18;
        a[1] = 1e18;
        t[0] = cUSD;
        t[1] = cUSD;
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(AgentActivityOracle.DuplicateTxHash.selector, dup));
        oracle.submitActivity(AGENT_ID, h, a, t);
    }

    function test_SubmitActivity_RevertsOnDuplicateAcrossCalls() public {
        bytes32 dup = keccak256("dup");
        (bytes32[] memory h, uint256[] memory a, address[] memory t) = _one(dup, 1e18, cUSD);
        vm.prank(alice);
        oracle.submitActivity(AGENT_ID, h, a, t);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(AgentActivityOracle.DuplicateTxHash.selector, dup));
        oracle.submitActivity(AGENT_ID, h, a, t);

        assertTrue(oracle.consumedTxHash(dup));
    }

    // -----------------------------------------------------------------
    // Helpers
    // -----------------------------------------------------------------

    function _one(bytes32 hash, uint256 amount, address token)
        internal
        pure
        returns (bytes32[] memory h, uint256[] memory a, address[] memory t)
    {
        h = new bytes32[](1);
        a = new uint256[](1);
        t = new address[](1);
        h[0] = hash;
        a[0] = amount;
        t[0] = token;
    }
}
