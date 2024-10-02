// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";
import {PeerLink} from "../src/PeerLink.sol";

contract TestPeerLink is Test {
    PeerLink public peerLink;
    address public bobAddress = makeAddr("bob");
    address public aliceAddress = makeAddr("alice");
    address public samAddress = makeAddr("sam");

    function setUp() public {
        vm.deal(bobAddress, 500 ether);
        vm.deal(aliceAddress, 500 ether);
        vm.deal(samAddress, 500 ether);
        peerLink = new PeerLink();
    }

    function testFriendshipApproval() external {
        createAllUsers();
        vm.prank(bobAddress);
        peerLink.sendFriendRequest(aliceAddress);
        vm.startPrank(aliceAddress);
        peerLink.getIncomingRequests();
        peerLink.handleFriendRequest(bobAddress, true);
        peerLink.getFriends();
        peerLink.getFriendsInfo();
        vm.stopPrank();
        vm.prank(bobAddress);
        peerLink.getFriendsInfo();
    }

    function testFriendshipDenial() external {
        createAllUsers();
        vm.prank(bobAddress);
        peerLink.sendFriendRequest(aliceAddress);
        vm.startPrank(aliceAddress);
        peerLink.getIncomingRequests();
        peerLink.handleFriendRequest(bobAddress, false);
        peerLink.getIncomingRequests();
    }

    function testMessagingSystem() external {
        createAllUsers();
        makeFriendsBobAndAlice();
        vm.prank(bobAddress);
        peerLink.sendMessage{value: 200 ether}(
            aliceAddress,
            "Hey Alice! Welcome to Peer Link, here is one POL to get you started"
        );
        vm.prank(aliceAddress);
        peerLink.getMessages(bobAddress);
        peerLink.credBalance(aliceAddress);
        peerLink.credBalance(bobAddress);
    }

    function testUpdateMetadata() external {
        createAllUsers();
        vm.startPrank(bobAddress);
        peerLink.getUserInfo(bobAddress);
        peerLink.updateName(1, "Bob Smith");
        peerLink.updateBio(1, "Well ain't that about a bit*h.");
        peerLink.getUserInfo(bobAddress);
    }

    function testMetadataFunction() external {
        createAllUsers();
        vm.startPrank(bobAddress);
        uint256 bobId = peerLink.userIds(bobAddress);
        uint256 credBalance = peerLink.credBalance(bobAddress);
        peerLink.tokenURI(bobId);
        peerLink.increaseReputation(credBalance);
        peerLink.tokenURI(bobId);
        vm.stopPrank();
    }

    function testIncomingRequests() external {
        createAllUsers();
        vm.prank(bobAddress);
        peerLink.sendFriendRequest(aliceAddress);
        vm.prank(aliceAddress);
        peerLink.getIncomingRequests();
    }

    /*//////////////////////////////////////////////////////////////
                                INTERNAL
    //////////////////////////////////////////////////////////////*/

    function createAllUsers() private {
        createUser(
            bobAddress,
            "bob",
            "I am new to crypto, excited to use this app."
        );
        createUser(
            aliceAddress,
            "alice",
            "A seasoned blockchain expert. Here to meet friends and make payments simple."
        );
        createUser(
            samAddress,
            "sam",
            "New to blockchain, looking to meet friends who are engaged in crypto."
        );
    }

    function createUser(
        address addr,
        string memory name,
        string memory bio
    ) private {
        peerLink.mintUser(addr, name, bio);
    }

    function makeFriendsBobAndAlice() private {
        vm.prank(bobAddress);
        peerLink.sendFriendRequest(aliceAddress);
        vm.prank(aliceAddress);
        peerLink.handleFriendRequest(bobAddress, true);
    }
}
