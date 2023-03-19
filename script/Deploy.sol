// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import {Script} from "forge-std/Script.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {PRBProxyFactory} from "prb-proxy/PRBProxyFactory.sol";

import {LinearStrategy} from "faucets/strategies/LinearStrategy.sol";
import {FaucetMetadataRenderer} from "faucets/renderer/FaucetMetadataRenderer.sol";
import {ETHFaucet} from "faucets/ETHFaucet.sol";
import {SharedNFTLogic} from "@zoralabs/nft-editions-contracts/contracts/SharedNFTLogic.sol";
import {PtMonoFont} from "faucets/renderer/external/PTMonoFont.sol";
import {FaucetFactory} from "faucets/FaucetFactory.sol";
import {ERC20Faucet} from "faucets/ERC20Faucet.sol";
import {ZorbNFT} from "faucets/renderer/external/ZorbNFT.sol";
import {console} from "forge-std/console.sol";

import {ZoraActions} from "../src/ZoraActions.sol";

contract DeployConfig is Script {
    string internal deployments_path;
    string internal deployments;
    address internal deployer;

    function setUp() public {
        uint256 pvk = vm.envUint("PRIVATE_KEY");
        deployer = vm.rememberKey(pvk);

        bool redeploy = false;
        try vm.envBool("REDEPLOY") returns (bool a) {
            redeploy = a;
        } catch {}
        string memory dep_loc = "./foundry-deployments/";
        string memory dep_path = string.concat(dep_loc, Strings.toString(block.chainid));
        deployments_path = string.concat(dep_path, ".json");

        if (!redeploy) {
            try vm.readFile(deployments_path) returns (string memory prev_dep) {
                deployments = prev_dep;
            } catch {
                // create the file
                vm.writeFile(deployments_path, "{}");
            }
        } else {
            // create the file if it doesnt exist, overwrite it if it does
            vm.writeFile(deployments_path, "{}");
        }
    }

    // Prevents redeployment to a chain
    function noRedeploy(function() internal returns (address) fn, string memory contractName)
        internal
        returns (address, bool)
    {
        // check if the contract name is in deployments
        try vm.parseJson(deployments, contractName) returns (bytes memory deployedTo) {
            if (deployedTo.length > 0) {
                address someContract = abi.decode(deployedTo, (address));
                labelAndRecord(someContract, contractName);
                // some networks are ephemeral so we need to actually confirm it was deployed
                // by checking if code is nonzero
                if (someContract.code.length > 0) {
                    console.log(string.concat("skipping contract deployment for: ", contractName));
                    // we already have it deployed
                    return (someContract, false);
                }
            }
        } catch {}
        console.log(string.concat("deploying contract: ", contractName));
        vm.startBroadcast(deployer);
        address c = fn();
        vm.stopBroadcast();
        labelAndRecord(c, contractName);
        return (c, true);
    }

    function labelAndRecord(address c, string memory contractName) internal {
        vm.label(c, contractName);
        string memory a = vm.serializeAddress("onlyJsonInMemory", contractName, address(c));
        vm.writeFile(deployments_path, a);
    }
}

contract Dependencies is DeployConfig {
    address private font;
    address private zorbNFT;
    address private faucetMetadataRenderer;
    address private erc20Faucet;
    address private ethFaucet;
    address private sharedNFTLogic;
    address private faucetFactory;

    function deploySharedNftLogic() internal returns (address) {
        return address(new SharedNFTLogic());
    }

    function deployPtMonoFont() internal returns (address) {
        return address(new PtMonoFont());
    }

    function deployZorbNFT() internal returns (address) {
        assert(sharedNFTLogic != address(0));
        return address(new ZorbNFT(SharedNFTLogic(sharedNFTLogic)));
    }

    function deployFaucetMetadataRenderer() internal returns (address) {
        assert(sharedNFTLogic != address(0));
        assert(zorbNFT != address(0));
        assert(font != address(0));
        return address(new FaucetMetadataRenderer(SharedNFTLogic(sharedNFTLogic), zorbNFT, PtMonoFont(font)));
    }

    function deployFaucetFactory() internal returns (address) {
        assert(erc20Faucet != address(0));
        assert(ethFaucet != address(0));
        return address(new FaucetFactory(erc20Faucet, ethFaucet));
    }

    function deployLinearStrategy() internal returns (address) {
        return address(new LinearStrategy());
    }

    function deployETHFaucet() internal returns (address) {
        assert(faucetMetadataRenderer != address(0));
        return address(new ETHFaucet(FaucetMetadataRenderer(faucetMetadataRenderer)));
    }

    function deployERC20Faucet() internal returns (address) {
        assert(faucetMetadataRenderer != address(0));
        return address(new ERC20Faucet(FaucetMetadataRenderer(faucetMetadataRenderer)));
    }

    function run() public virtual {
        // address zorbRenderer = address(new ZorbNFT(sharedNFTLogic));
        // PtMonoFont font = new PtMonoFont();
        // FaucetMetadataRenderer faucetMetadataRenderer = new FaucetMetadataRenderer(sharedNFTLogic, zorbRenderer, font);
        // new FaucetFactory(address(new ERC20Faucet(faucetMetadataRenderer)), address(new ETHFaucet(faucetMetadataRenderer)));
        // new LinearStrategy();
        (sharedNFTLogic,) = noRedeploy(deploySharedNftLogic, "SharedNFTLogic");
        (zorbNFT,) = noRedeploy(deployZorbNFT, "ZorbNFT");
        (font,) = noRedeploy(deployPtMonoFont, "PtMonoFont");
        (faucetMetadataRenderer,) = noRedeploy(deployFaucetMetadataRenderer, "FaucetMetadataRenderer");
        (erc20Faucet,) = noRedeploy(deployERC20Faucet, "ERC20Faucet");
        (ethFaucet,) = noRedeploy(deployETHFaucet, "ETHFaucet");
        (faucetFactory,) = noRedeploy(deployFaucetFactory, "FaucetFactory");
    }
}

contract OurContracts is Dependencies {
    address private zoraActions;
    address private proxyFactory;

    function deployZoraActions() internal returns (address) {
        return address(new ZoraActions());
    }

    function deployPRBProxyFactory() internal returns (address) {
        return address(new PRBProxyFactory());
    }

    function run() public override {
        super.run();
        (zoraActions,) = noRedeploy(deployZoraActions, "ZoraActions");
        (proxyFactory,) = noRedeploy(deployPRBProxyFactory, "PRBProxyFactory");
    }
}
