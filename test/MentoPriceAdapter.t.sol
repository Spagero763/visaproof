// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {MentoPriceAdapter, ISortedOracles} from "../src/MentoPriceAdapter.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/// @dev Mock Mento SortedOracles seeded with live Celo mainnet readings.
///      Rates captured from mainnet feed 0xefB84935239dAcdecF7c5bA76d8dE40b077B7b33:
///      cUSD = 71677580000000000000000, cEUR = 61725520000000000000000,
///      both with denominator 1e24. rate/denominator is token units per 1 CELO.
contract MockSortedOracles is ISortedOracles {
    mapping(address => uint256) public rates;
    mapping(address => uint256) public denominators;

    function setRate(address rateFeedId, uint256 rate, uint256 denominator) external {
        rates[rateFeedId] = rate;
        denominators[rateFeedId] = denominator;
    }

    function medianRate(address rateFeedId) external view returns (uint256 rate, uint256 denominator) {
        return (rates[rateFeedId], denominators[rateFeedId]);
    }
}

/// @dev Minimal ERC20 exposing a settable decimals() for configureToken tests.
contract MockToken is IERC20Metadata {
    uint8 private _decimals;

    constructor(uint8 dec) {
        _decimals = dec;
    }

    function decimals() external view returns (uint8) {
        return _decimals;
    }

    function name() external pure returns (string memory) {
        return "Mock";
    }

    function symbol() external pure returns (string memory) {
        return "MCK";
    }

    function totalSupply() external pure returns (uint256) {
        return 0;
    }

    function balanceOf(address) external pure returns (uint256) {
        return 0;
    }

    function transfer(address, uint256) external pure returns (bool) {
        return false;
    }

    function allowance(address, address) external pure returns (uint256) {
        return 0;
    }

    function approve(address, uint256) external pure returns (bool) {
        return false;
    }

    function transferFrom(address, address, uint256) external pure returns (bool) {
        return false;
    }
}

contract MentoPriceAdapterTest is Test {
    MentoPriceAdapter internal adapter;
    MockSortedOracles internal oracles;

    address internal owner = makeAddr("owner");
    address internal stranger = makeAddr("stranger");

    // Live mainnet feed addresses (used only as identifiers in the mock).
    address internal cUSD = 0x765DE816845861e75A25fCA122bb6898B8B1282a;
    address internal cEUR = 0xD8763CBa276a3738E6DE85b4b3bF5FDed6D6cA73;
    address internal cREAL = 0xe8537a3d056DA446677B9E9d6c5dB704EaAb4787;
    address internal USDT = 0x48065fbBE25f71C9282ddf5e1cD6D6A887483D5e;
    address internal USDC = 0xcebA9300f2b948710d2653dD7B07f33A8B32118C;

    // Live mainnet readings, denominator 1e24.
    uint256 internal constant RATE_CUSD = 71677580000000000000000;
    uint256 internal constant RATE_CEUR = 61725520000000000000000;
    uint256 internal constant DENOM = 1e24;

    event SortedOraclesUpdated(address indexed sortedOracles);
    event TokenConfigured(address indexed token, MentoPriceAdapter.Mode mode, uint8 decimals);
    event TokenRemoved(address indexed token);

    function setUp() public {
        oracles = new MockSortedOracles();
        oracles.setRate(cUSD, RATE_CUSD, DENOM);
        oracles.setRate(cEUR, RATE_CEUR, DENOM);

        adapter = new MentoPriceAdapter(address(oracles), cUSD, owner);
    }

    // -----------------------------------------------------------------
    // Constructor
    // -----------------------------------------------------------------

    function test_Constructor_SetsState() public view {
        assertEq(address(adapter.sortedOracles()), address(oracles));
        assertEq(adapter.cUSD(), cUSD);
        assertEq(adapter.owner(), owner);

        (MentoPriceAdapter.Mode mode, uint8 dec) = adapter.configOf(cUSD);
        assertEq(uint8(mode), uint8(MentoPriceAdapter.Mode.Pegged));
        assertEq(dec, 18);
    }

    function test_Constructor_EmitsCUSDConfigured() public {
        vm.expectEmit(true, false, false, true);
        emit TokenConfigured(cUSD, MentoPriceAdapter.Mode.Pegged, 18);
        new MentoPriceAdapter(address(oracles), cUSD, owner);
    }

    function test_Constructor_RevertsOnZeroSortedOracles() public {
        vm.expectRevert(MentoPriceAdapter.ZeroAddress.selector);
        new MentoPriceAdapter(address(0), cUSD, owner);
    }

    function test_Constructor_RevertsOnZeroCUSD() public {
        vm.expectRevert(MentoPriceAdapter.ZeroAddress.selector);
        new MentoPriceAdapter(address(oracles), address(0), owner);
    }

    // -----------------------------------------------------------------
    // configureToken
    // -----------------------------------------------------------------

    function test_ConfigureToken_ReadsDecimalsFromToken() public {
        MockToken usdt = new MockToken(6);

        vm.expectEmit(true, false, false, true);
        emit TokenConfigured(address(usdt), MentoPriceAdapter.Mode.Pegged, 6);

        vm.prank(owner);
        adapter.configureToken(address(usdt), MentoPriceAdapter.Mode.Pegged);

        (MentoPriceAdapter.Mode mode, uint8 dec) = adapter.configOf(address(usdt));
        assertEq(uint8(mode), uint8(MentoPriceAdapter.Mode.Pegged));
        assertEq(dec, 6);
    }

    function test_ConfigureToken_RevertsWhenNotOwner() public {
        MockToken usdt = new MockToken(6);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        vm.prank(stranger);
        adapter.configureToken(address(usdt), MentoPriceAdapter.Mode.Pegged);
    }

    function test_ConfigureToken_RevertsOnZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(MentoPriceAdapter.ZeroAddress.selector);
        adapter.configureToken(address(0), MentoPriceAdapter.Mode.Pegged);
    }

    function test_ConfigureToken_RevertsOnUnsupportedMode() public {
        MockToken tok = new MockToken(18);
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(MentoPriceAdapter.UnsupportedToken.selector, address(tok)));
        adapter.configureToken(address(tok), MentoPriceAdapter.Mode.Unsupported);
    }

    // -----------------------------------------------------------------
    // configureTokenWithDecimals
    // -----------------------------------------------------------------

    function test_ConfigureTokenWithDecimals_Succeeds() public {
        vm.expectEmit(true, false, false, true);
        emit TokenConfigured(cEUR, MentoPriceAdapter.Mode.Mento, 18);

        vm.prank(owner);
        adapter.configureTokenWithDecimals(cEUR, MentoPriceAdapter.Mode.Mento, 18);

        (MentoPriceAdapter.Mode mode, uint8 dec) = adapter.configOf(cEUR);
        assertEq(uint8(mode), uint8(MentoPriceAdapter.Mode.Mento));
        assertEq(dec, 18);
    }

    function test_ConfigureTokenWithDecimals_RevertsWhenNotOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        vm.prank(stranger);
        adapter.configureTokenWithDecimals(cEUR, MentoPriceAdapter.Mode.Mento, 18);
    }

    function test_ConfigureTokenWithDecimals_RevertsOnZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(MentoPriceAdapter.ZeroAddress.selector);
        adapter.configureTokenWithDecimals(address(0), MentoPriceAdapter.Mode.Mento, 18);
    }

    function test_ConfigureTokenWithDecimals_RevertsOnUnsupportedMode() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(MentoPriceAdapter.UnsupportedToken.selector, cEUR));
        adapter.configureTokenWithDecimals(cEUR, MentoPriceAdapter.Mode.Unsupported, 18);
    }

    // -----------------------------------------------------------------
    // removeToken
    // -----------------------------------------------------------------

    function test_RemoveToken_Succeeds() public {
        vm.prank(owner);
        adapter.configureTokenWithDecimals(cEUR, MentoPriceAdapter.Mode.Mento, 18);

        vm.expectEmit(true, false, false, false);
        emit TokenRemoved(cEUR);

        vm.prank(owner);
        adapter.removeToken(cEUR);

        (MentoPriceAdapter.Mode mode,) = adapter.configOf(cEUR);
        assertEq(uint8(mode), uint8(MentoPriceAdapter.Mode.Unsupported));
    }

    function test_RemoveToken_RevertsWhenNotOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        vm.prank(stranger);
        adapter.removeToken(cEUR);
    }

    // -----------------------------------------------------------------
    // setSortedOracles
    // -----------------------------------------------------------------

    function test_SetSortedOracles_Succeeds() public {
        MockSortedOracles next = new MockSortedOracles();

        vm.expectEmit(true, false, false, false);
        emit SortedOraclesUpdated(address(next));

        vm.prank(owner);
        adapter.setSortedOracles(address(next));

        assertEq(address(adapter.sortedOracles()), address(next));
    }

    function test_SetSortedOracles_RevertsWhenNotOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        vm.prank(stranger);
        adapter.setSortedOracles(address(oracles));
    }

    function test_SetSortedOracles_RevertsOnZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(MentoPriceAdapter.ZeroAddress.selector);
        adapter.setSortedOracles(address(0));
    }

    // -----------------------------------------------------------------
    // toCUSD - pegged
    // -----------------------------------------------------------------

    function test_ToCUSD_PeggedCUSD_PassesThrough() public view {
        // cUSD is 18 decimals, pegged 1:1.
        assertEq(adapter.toCUSD(cUSD, 100e18), 100e18);
    }

    function test_ToCUSD_Pegged6Decimals_NormalisesUp() public {
        // USDT/USDC are 6 decimals: 100 USDT -> 100e18 cUSD.
        vm.prank(owner);
        adapter.configureTokenWithDecimals(USDT, MentoPriceAdapter.Mode.Pegged, 6);
        assertEq(adapter.toCUSD(USDT, 100e6), 100e18);
    }

    function test_ToCUSD_Pegged6Decimals_USDC() public {
        vm.prank(owner);
        adapter.configureTokenWithDecimals(USDC, MentoPriceAdapter.Mode.Pegged, 6);
        assertEq(adapter.toCUSD(USDC, 2_500e6), 2_500e18);
    }

    function test_ToCUSD_Pegged24Decimals_NormalisesDown() public {
        // Exercise the decimals > 18 branch of _to18.
        MockToken big = new MockToken(24);
        vm.prank(owner);
        adapter.configureToken(address(big), MentoPriceAdapter.Mode.Pegged);
        assertEq(adapter.toCUSD(address(big), 100e24), 100e18);
    }

    // -----------------------------------------------------------------
    // toCUSD - Mento routed through CELO
    // -----------------------------------------------------------------

    function test_ToCUSD_MentoCEUR_AppliesLiveRate() public {
        vm.prank(owner);
        adapter.configureTokenWithDecimals(cEUR, MentoPriceAdapter.Mode.Mento, 18);

        // 100 cEUR -> cUSD: 100 * rate(cUSD) / rate(cEUR).
        // 100e18 * 71677580.. / 61725520.. ~= 116.12e18 (EUR/USD ~ 1.161).
        uint256 value = adapter.toCUSD(cEUR, 100e18);
        uint256 expected = (uint256(100e18) * RATE_CUSD) / RATE_CEUR;
        assertEq(value, expected);
        assertApproxEqRel(value, 116.12e18, 0.001e18);
    }

    function test_ToCUSD_MentoCEUR_OneToOneWhenRatesEqual() public {
        // If a c-stable shares cUSD's CELO rate, value equals the amount.
        oracles.setRate(cEUR, RATE_CUSD, DENOM);
        vm.prank(owner);
        adapter.configureTokenWithDecimals(cEUR, MentoPriceAdapter.Mode.Mento, 18);
        assertEq(adapter.toCUSD(cEUR, 100e18), 100e18);
    }

    function test_ToCUSD_MentoHandlesDifferentDenominators() public {
        // Denominator cancellation: token feed on a different denominator
        // must still yield the rate-ratio result.
        oracles.setRate(cREAL, RATE_CEUR / 1e6, DENOM / 1e6);
        vm.prank(owner);
        adapter.configureTokenWithDecimals(cREAL, MentoPriceAdapter.Mode.Mento, 18);

        uint256 value = adapter.toCUSD(cREAL, 100e18);
        uint256 expected = (uint256(100e18) * RATE_CUSD) / RATE_CEUR;
        assertEq(value, expected);
    }

    function test_ToCUSD_MentoZeroAmount() public {
        vm.prank(owner);
        adapter.configureTokenWithDecimals(cEUR, MentoPriceAdapter.Mode.Mento, 18);
        assertEq(adapter.toCUSD(cEUR, 0), 0);
    }

    // -----------------------------------------------------------------
    // toCUSD - reverts
    // -----------------------------------------------------------------

    function test_ToCUSD_RevertsOnUnsupportedToken() public {
        vm.expectRevert(abi.encodeWithSelector(MentoPriceAdapter.UnsupportedToken.selector, cREAL));
        adapter.toCUSD(cREAL, 1e18);
    }

    function test_ToCUSD_RevertsWhenTokenRateZero() public {
        vm.prank(owner);
        adapter.configureTokenWithDecimals(cREAL, MentoPriceAdapter.Mode.Mento, 18);
        // cREAL rate not seeded -> medianRate returns 0.
        vm.expectRevert(abi.encodeWithSelector(MentoPriceAdapter.InvalidRate.selector, cREAL));
        adapter.toCUSD(cREAL, 1e18);
    }

    function test_ToCUSD_RevertsWhenCUSDRateZero() public {
        // Wipe cUSD feed so rUsd == 0 while token rate is valid.
        oracles.setRate(cUSD, 0, DENOM);
        vm.prank(owner);
        adapter.configureTokenWithDecimals(cEUR, MentoPriceAdapter.Mode.Mento, 18);
        vm.expectRevert(abi.encodeWithSelector(MentoPriceAdapter.InvalidRate.selector, cEUR));
        adapter.toCUSD(cEUR, 1e18);
    }

    // -----------------------------------------------------------------
    // Fuzz
    // -----------------------------------------------------------------

    function testFuzz_ToCUSD_PeggedPassThrough(uint256 amount) public view {
        amount = bound(amount, 0, 1e30);
        assertEq(adapter.toCUSD(cUSD, amount), amount);
    }

    function testFuzz_ToCUSD_MentoMatchesRateRatio(uint256 amount) public {
        amount = bound(amount, 0, 1e30);
        vm.prank(owner);
        adapter.configureTokenWithDecimals(cEUR, MentoPriceAdapter.Mode.Mento, 18);

        uint256 value = adapter.toCUSD(cEUR, amount);
        // mulDiv twice with equal denominators reduces to amount * rUsd / rTok.
        uint256 expected = (amount * RATE_CUSD) / RATE_CEUR;
        assertEq(value, expected);
    }
}
