// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import { Test } from "forge-std/Test.sol";
import {PRBProxy } from "prb-proxy/PRBProxy.sol";
import {PRBProxyFactory} from "prb-proxy/PRBProxyFactory.sol";
import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import {ZoraActions} from "../src/ZoraActions.sol";

import {FaucetFactory} from "faucets/FaucetFactory.sol";
import {ERC20Faucet} from "faucets/ERC20Faucet.sol";
import {IFaucet} from "faucets/IFaucet.sol";
import {ETHFaucet} from "faucets/ETHFaucet.sol";
import {LinearStrategy} from "faucets/strategies/LinearStrategy.sol";
import {FaucetMetadataRenderer} from "faucets/renderer/FaucetMetadataRenderer.sol";
import {SharedNFTLogic} from "@zoralabs/nft-editions-contracts/contracts/SharedNFTLogic.sol";
import {PtMonoFont} from "faucets/renderer/external/PTMonoFont.sol";
import {ZorbNFT} from "faucets/renderer/external/ZorbNFT.sol";

contract FaucetsTest is Test {
    ZoraActions public actions;
    FaucetFactory public faucetFactory;
    LinearStrategy public linearStrategy;

    // event isn't exported from IERC20 😭
    event Transfer(address indexed from, address indexed to, uint256 value);

    function setUp() public virtual {
        actions = new ZoraActions();
        SharedNFTLogic sharedNFTLogic = new SharedNFTLogic();
        address zorbRenderer = address(new ZorbNFT(sharedNFTLogic));
        PtMonoFont font = new PtMonoFont();
        FaucetMetadataRenderer renderer = new FaucetMetadataRenderer(sharedNFTLogic, zorbRenderer, font);
        faucetFactory = new FaucetFactory(address(new ERC20Faucet(renderer)), address(new ETHFaucet(renderer)));
        linearStrategy = new LinearStrategy();
    }
}

contract PRBProxyTest is FaucetsTest {
    PRBProxy internal proxy;
    ERC20 internal mockToken;
    address internal user = vm.addr(1);

    function setUp() public override virtual {
        super.setUp();

        mockToken = new ERC20("mock token", "MOCK");
        PRBProxyFactory factory = new PRBProxyFactory();
        vm.prank(user);
        proxy = PRBProxy(factory.deploy());
        deal(address(mockToken), address(proxy), 100 ether);
    }

}
contract WHEN_creating_two_streams is PRBProxyTest {
    address private wagieWalter;
    address private salarySophie;
    ERC20Faucet private faucet;
    uint256[] private ids;
    function setUp() public override {
        super.setUp();
        wagieWalter = vm.addr(2);
        salarySophie = vm.addr(3);
        address[] memory recipients = new address[](2);
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1 ether;
        amounts[1] = 5 ether;
        recipients[0] = wagieWalter;
        recipients[1] = salarySophie;
        vm.prank(user);
        uint256[] memory ids_local = new uint256[](2);
        ids_local = abi.decode(proxy.execute(
            address(actions),
            abi.encodeWithSelector(
                ZoraActions.createMultipleStreams.selector,
                address(faucetFactory),
                address(mockToken),
                address(linearStrategy),
                90 days,
                recipients,
                amounts
            )
        ), (uint256[]));

        for (uint256 i = 0; i < ids_local.length ; i++){
            ids.push(ids_local[i]);
        }
        faucet = ERC20Faucet(faucetFactory.faucetForTokenView(address(mockToken)));
    }

    function test_THEN_their_ids_are_auto_incremental() public {
        assertEq(ids[0], 0);
        assertEq(ids[1], 1);
    }

    function test_THEN_their_ownership_is_correct() public {
        assertEq(faucet.totalSupply(), 2);
        assertEq(faucet.balanceOf(user), 0);
        assertEq(faucet.balanceOf(address(proxy)), 0);
        assertEq(faucet.ownerOf(ids[0]), wagieWalter);
        assertEq(faucet.ownerOf(ids[1]), salarySophie);
    }

    function test_THEN_the_faucets_are_properly_configured() public {
        ERC20Faucet.FaucetDetails memory walterStream = faucet.getFaucetDetailsForToken(ids[0]);
        ERC20Faucet.FaucetDetails memory sophieStream = faucet.getFaucetDetailsForToken(ids[1]);
        assertEq(sophieStream.totalAmount, 5 ether);
        assertEq(sophieStream.supplier, address(proxy));
        assertEq(sophieStream.faucetStrategy, address(linearStrategy));
        assertEq(sophieStream.canBeRescinded, false);
        assertEq(sophieStream.faucetStart, block.timestamp);
        assertEq(sophieStream.faucetExpiry, block.timestamp + 90 days);
        assertEq(sophieStream.claimedAmount, 0);

        assertEq(walterStream.totalAmount, 1 ether);
        assertEq(walterStream.supplier, address(proxy));
        assertEq(walterStream.faucetStrategy, address(linearStrategy));
        assertEq(walterStream.canBeRescinded, false);
        assertEq(walterStream.faucetStart, block.timestamp);
        assertEq(walterStream.faucetExpiry, block.timestamp + 90 days);
        assertEq(walterStream.claimedAmount, 0);
    }
}

contract GIVEN_an_open_stream is PRBProxyTest {
    address internal alice;
    uint256 internal streamId;
    ERC20Faucet internal faucet;
    function setUp() public override {
        super.setUp();

        alice = vm.addr(2);

        address[] memory recipients = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1 ether;
        recipients[0] = alice;
        vm.prank(user);
        uint256[] memory ids_local = new uint256[](1);
        ids_local = abi.decode(proxy.execute(
            address(actions),
            abi.encodeWithSelector(
                ZoraActions.createMultipleStreams.selector,
                address(faucetFactory),
                address(mockToken),
                address(linearStrategy),
                90 days,
                recipients,
                amounts
            )
        ), (uint256[]));

        faucet = ERC20Faucet(faucetFactory.faucetForTokenView(address(mockToken)));
        streamId = ids_local[0];
    }

    function test_THEN_the_stream_cannot_be_rescinded() public {
        vm.prank(address(proxy));
        vm.expectRevert(IFaucet.RescindUnrescindable.selector);
        faucet.rescind(address(user), streamId);
    }

    function test_THEN_it_cannot_be_claimed_right_away() public {
        vm.prank(alice);
        faucet.claim(address(alice), streamId);
        ERC20Faucet.FaucetDetails memory stream = faucet.getFaucetDetailsForToken(streamId);
        assertEq(stream.claimedAmount, 0);
    }

    function test_WHEN_45_days_pass_then_half_of_the_stream_can_be_redeemed() public {
        vm.prank(alice);
        vm.warp(45 days);
        faucet.claim(address(alice), streamId);
        ERC20Faucet.FaucetDetails memory stream = faucet.getFaucetDetailsForToken(streamId);
        assertApproxEqAbs(stream.claimedAmount,  0.5 ether, 0.00001 ether);
    }

    function test_WHEN_100_days_pass_then_all_of_the_stream_can_be_redeemed() public {
        vm.prank(alice);
        vm.warp(100 days);
        vm.expectEmit(true,true,true,true);
        emit Transfer(address(faucet), address(alice), 1 ether);
        faucet.claim(address(alice), streamId);
    }

    function test_WHEN_the_stream_is_emptied_THEN_the_NFT_is_burnt() public {
        vm.prank(alice);
        vm.warp(100 days);
        faucet.claim(address(alice), streamId);
        ERC20Faucet.FaucetDetails memory stream = faucet.getFaucetDetailsForToken(streamId);

        assertEq(stream.totalAmount, 0);
        assertEq(stream.supplier, address(0));
        assertEq(stream.faucetStrategy, address(0));
        assertEq(stream.canBeRescinded, false);
        assertEq(stream.faucetStart, 0);
        assertEq(stream.faucetExpiry, 0);
        assertEq(stream.claimedAmount, 0);
        assertEq(faucet.totalSupply(), 0);
    }
}
