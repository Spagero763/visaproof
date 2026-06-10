// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {MentoPriceAdapter} from "../src/MentoPriceAdapter.sol";
import {AgentActivityOracle} from "../src/AgentActivityOracle.sol";
import {AgentPassport} from "../src/AgentPassport.sol";
import {AgentVisaRegistry} from "../src/AgentVisaRegistry.sol";
import {CeloAddresses} from "./CeloAddresses.sol";

/// @title Deploy
/// @notice Deploys the VisaProof stack to Celo and wires it end to end.
/// @dev Order matters: the price adapter is needed by the activity oracle,
///      which is needed by both the passport and the registry.
///
///        MentoPriceAdapter
///                |
///        AgentActivityOracle  (priceOracle = adapter)
///                |
///        AgentPassport        (activityOracle = oracle)
///                |
///        AgentVisaRegistry    (passport + oracle)
///
///      After deployment the script configures the price adapter and the
///      oracle's supported token set so submissions price correctly from
///      block one.
///
///      Run with:
///        forge script script/Deploy.s.sol:Deploy \
///          --rpc-url celo --account visaproof-deployer \
///          --sender 0xYourDeployerAddress --broadcast --verify
///
///      `--sender` must match the keystore address. The script captures
///      msg.sender before broadcasting to set the protocol owner, and the
///      subsequent admin calls are sent from the same address. Without
///      `--sender`, msg.sender defaults to forge's placeholder and the
///      configure calls revert with OwnableUnauthorizedAccount.
contract Deploy is Script {
    function run()
        external
        returns (
            MentoPriceAdapter adapter,
            AgentActivityOracle oracle,
            AgentPassport passport,
            AgentVisaRegistry registry
        )
    {
        address owner = msg.sender;
        require(
            owner != 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38,
            "Pass --sender <your address>; forge default sender will not own the contracts"
        );

        vm.startBroadcast();

        // 1. Price adapter. cUSD is registered as pegged/18 by the constructor.
        adapter = new MentoPriceAdapter(CeloAddresses.SORTED_ORACLES, CeloAddresses.cUSD, owner);

        // Mento c-stables route through CELO via SortedOracles.
        adapter.configureTokenWithDecimals(CeloAddresses.cEUR, MentoPriceAdapter.Mode.Mento, 18);
        adapter.configureTokenWithDecimals(CeloAddresses.cREAL, MentoPriceAdapter.Mode.Mento, 18);

        // Bridged USD stables are pegged 1:1, normalised from 6 decimals.
        adapter.configureTokenWithDecimals(CeloAddresses.USDT, MentoPriceAdapter.Mode.Pegged, 6);
        adapter.configureTokenWithDecimals(CeloAddresses.USDC, MentoPriceAdapter.Mode.Pegged, 6);

        // 2. Activity oracle. Accepts submissions and prices them via the adapter.
        oracle = new AgentActivityOracle(CeloAddresses.IDENTITY_REGISTRY, address(adapter), owner);

        oracle.setSupportedToken(CeloAddresses.cUSD, true);
        oracle.setSupportedToken(CeloAddresses.cEUR, true);
        oracle.setSupportedToken(CeloAddresses.cREAL, true);
        oracle.setSupportedToken(CeloAddresses.USDT, true);
        oracle.setSupportedToken(CeloAddresses.USDC, true);

        // 3. Passport. Reads verified activity for tier computation and gates
        //    registration on a fresh Self Agent ID proof of human.
        passport = new AgentPassport(CeloAddresses.IDENTITY_REGISTRY, address(oracle), CeloAddresses.SELF_AGENT_REGISTRY);

        // 4. Registry. Coordinates applications, leaderboard and discovery.
        registry = new AgentVisaRegistry(address(passport), CeloAddresses.IDENTITY_REGISTRY, address(oracle));

        vm.stopBroadcast();

        console2.log("MentoPriceAdapter ", address(adapter));
        console2.log("AgentActivityOracle", address(oracle));
        console2.log("AgentPassport     ", address(passport));
        console2.log("AgentVisaRegistry ", address(registry));
    }
}
