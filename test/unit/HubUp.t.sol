// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.23;

import {HubUp} from "contracts/HubUp.sol";
import {Test} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import "forge-std/console.sol";

contract MockERC20 is ERC20 {
    constructor(uint256 initialSupply) ERC20("Mock Token", "MTK") {
        _mint(msg.sender, initialSupply);
    }
}

contract UnitHubUp is Test {
    function computeExpectedEventCode(
        address sender,
        uint256 timestamp
    ) internal pure returns (string memory) {
        uint256 randomNum = uint256(
            keccak256(abi.encodePacked(timestamp, sender))
        ) % 1000000;
        return toString(randomNum);
    }

    function toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    address internal _owner = makeAddr("owner");
    address internal _host = makeAddr("host");
    IERC20 internal _token;
    uint256 internal _initialBalance = 100 ether;

    HubUp internal _hubUp;

    event EventCreated(
        uint256 indexed eventId,
        address indexed host,
        string eventCode
    );
    event EventFormalized(uint256 indexed eventId);
    event ParticipantJoined(
        uint256 indexed eventId,
        address indexed participant
    );
    event ParticipantLeft(uint256 indexed eventId, address indexed participant);
    event StakeClaimed(
        uint256 indexed eventId,
        address indexed participant,
        uint256 amount
    );
    event PaymentClaimed(
        uint256 indexed eventId,
        address indexed host,
        uint256 amount
    );
    event EventPaymentBlocked(uint256 indexed eventId);
    event EventPaymentUnblocked(uint256 indexed eventId);
    event PaymentSentBack(uint256 indexed eventId, address indexed participant);

    uint256 firstEventId = 0;
    uint256 startTime = block.timestamp + 1 hours;
    uint256 endTime = startTime + 2 hours;
    uint256 price = 10 ether;
    uint256 stakeAmount = 5 ether;
    uint256 minParticipants = 1;
    uint256 maxParticipants = 5;

    function setUp() external {
        // Deploy a mock ERC20 token and assign initial balances
        _token = new MockERC20(_initialBalance * 10);

        // Assign initial balance to owner and host
        _token.transfer(_owner, _initialBalance);
        _token.transfer(_host, _initialBalance);

        // Deploy the HubUp contract
        vm.prank(_owner);
        _hubUp = new HubUp(address(_token));

        // Ensure the owner and host have the correct balances
        assertEq(_token.balanceOf(_owner), _initialBalance);
        assertEq(_token.balanceOf(_host), _initialBalance);
    }

    function testCreateEvent() public {
        uint256 requiredStake = (stakeAmount * maxParticipants) / 2;
        // Compute the expected event code before calling the function
        string memory expectedEventCode = computeExpectedEventCode(
            _host,
            block.timestamp
        );
        console.log("block.timestamp test:", block.timestamp);

        console.log("eventCode test:", expectedEventCode);

        // Approve the HubUp contract to spend the host's tokens
        vm.prank(_host);
        _token.approve(address(_hubUp), requiredStake);

        // Expect EventCreated to be emitted
        vm.expectEmit(true, true, true, true);
        emit EventCreated(firstEventId, _host, expectedEventCode); // Event code is generated, hence kept as "" for now

        // Prank the call from the host address
        vm.prank(_host);

        // Call the createEvent function
        _hubUp.createEvent(
            startTime,
            endTime,
            price,
            stakeAmount,
            minParticipants,
            maxParticipants
        );

        console.log(
            "contract balance after createEvent",
            _token.balanceOf(address(_hubUp))
        );

        (
            address host,
            uint256 eventStartTime,
            uint256 eventEndTime,
            uint256 eventPrice,
            uint256 eventStakeAmount,
            uint256 eventMinParticipants,
            uint256 eventMaxParticipants,
            uint256 eventParticipantCount,
            uint256 eventUnstakedParticipantCount,
            uint256 eventTotalParticipantsJoined,
            bool isFinalized,
            bool isPaymentBlocked,
            string memory eventCode
        ) = _hubUp.events(0);

        // Perform assertions
        assertEq(host, _host);
        assertEq(eventStartTime, startTime);
        assertEq(eventEndTime, endTime);
        assertEq(eventPrice, price);
        assertEq(eventStakeAmount, stakeAmount);
        assertEq(eventMinParticipants, minParticipants);
        assertEq(eventMaxParticipants, maxParticipants);
        assertEq(eventParticipantCount, 0);
        assertEq(eventUnstakedParticipantCount, 0);
        assertEq(eventTotalParticipantsJoined, 0);
        assertEq(isFinalized, false);
        assertEq(isPaymentBlocked, false);
        assert(bytes(eventCode).length > 0); // eventCode should be generated and non-empty
    }

    uint256 public participantCounter;

    function testJoinEvent() public returns (address) {
        uint256 nextEventId = _hubUp.nextEventId();
        // First, create an event if nextEventId is 0
        if (nextEventId == 0) {
            testCreateEvent();
        }

        // Define the eventId and the participant
        uint256 eventId = 0; // Assuming the first event created has ID 0
        // Increment the participant counter and use it to generate a unique participant address
        participantCounter++;
        address participant = makeAddr(
            string(
                abi.encodePacked("participant", toString(participantCounter))
            )
        );

        // Set up the participant's balance and approve the contract to spend the tokens
        uint256 totalCost = price + stakeAmount;

        // Give the participant enough tokens
        deal(address(_token), participant, totalCost);

        // Record the initial balances
        uint256 initialParticipantBalance = _token.balanceOf(participant);
        uint256 initialContractBalance = _token.balanceOf(address(_hubUp));

        // Approve the contract to spend the participant's tokens
        vm.prank(participant);
        _token.approve(address(_hubUp), totalCost);

        // Assert that the participant count has increased
        (
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            // Skipping irrelevant fields
            uint256 eventParticipantCountBefore,
            ,
            uint256 eventTotalParticipantsJoinedBefore,
            ,
            ,

        ) = _hubUp.events(eventId);

        // Expect ParticipantJoined event to be emitted
        vm.expectEmit(true, true, false, true);
        emit ParticipantJoined(eventId, participant);

        // Prank the call from the participant address to join the event
        vm.prank(participant);

        // Call the joinEvent function
        _hubUp.joinEvent(eventId);

        // Assert that the participant count has increased
        (
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            // Skipping irrelevant fields
            uint256 eventParticipantCount,
            ,
            uint256 eventTotalParticipantsJoined,
            bool isFinalized, // Skipping irrelevant fields
            ,

        ) = _hubUp.events(eventId);

        assertEq(eventParticipantCount - eventParticipantCountBefore, 1); // Should be 1 since only one participant joined
        assertEq(
            eventTotalParticipantsJoined - eventTotalParticipantsJoinedBefore,
            1
        ); // Should also be 1
        assertEq(isFinalized, eventParticipantCount >= 1); // Event should be finalized since minParticipants was 1

        // Check token balances after joining the event
        uint256 finalParticipantBalance = _token.balanceOf(participant);
        uint256 finalContractBalance = _token.balanceOf(address(_hubUp));

        // Assert that the participant's balance decreased by the total cost
        assertEq(
            finalParticipantBalance,
            initialParticipantBalance - totalCost
        );

        // Assert that the contract's balance increased by the total cost
        assertEq(finalContractBalance, initialContractBalance + totalCost);
        return participant;
    }

    function testLeaveEventByParticipant() public {
        // Use testJoinEvent to get the participant's address
        address participant = testJoinEvent();
        uint256 eventId = 0; // Assuming the first event created has ID 0

        // Record the participant count before leaving the event
        (, , , , , , , uint256 initialParticipantCount, , , , , ) = _hubUp
            .events(eventId);

        // Expect the ParticipantLeft event to be emitted
        vm.expectEmit(true, true, false, true);
        emit ParticipantLeft(eventId, participant);

        // Prank the call from the participant address to leave the event
        vm.prank(participant);

        // Call the leaveEvent function
        _hubUp.leaveEvent(eventId, participant);

        // Assert that the participant count has decreased
        (, , , , , , , uint256 finalParticipantCount, , , , , ) = _hubUp.events(
            eventId
        );
        assertEq(finalParticipantCount, initialParticipantCount - 1);
    }

    function testLeaveEventByHost() public {
        // Use testJoinEvent to get the participant's address
        address participant = testJoinEvent();
        uint256 eventId = 0; // Assuming the first event created has ID 0

        // Record the participant count before leaving the event
        (, , , , , , , uint256 initialParticipantCount, , , , , ) = _hubUp
            .events(eventId);

        // Expect the ParticipantLeft event to be emitted
        vm.expectEmit(true, true, false, true);
        emit ParticipantLeft(eventId, participant);

        // Prank the call from the participant address to leave the event
        vm.prank(_host);

        // Call the leaveEvent function
        _hubUp.leaveEvent(eventId, participant);

        // Assert that the participant count has decreased
        (, , , , , , , uint256 finalParticipantCount, , , , , ) = _hubUp.events(
            eventId
        );
        assertEq(finalParticipantCount, initialParticipantCount - 1);
    }

    function testClaimParticipantStake() public {
        // Use testJoinEvent to get the participant's address
        address participant = testJoinEvent();

        uint256 eventId = 0; // Assuming the first event created has ID 0

        // Assume the event code is known (you can extract it using similar logic as in the testCreateEvent function)
        (, , , , , , , , , , , , string memory eventCode) = _hubUp.events(0);

        // Record the participant's initial balance
        uint256 initialParticipantBalance = _token.balanceOf(participant);

        // Prank the call from the participant address to claim the stake
        vm.prank(participant);

        // Expect the StakeClaimed event to be emitted
        vm.expectEmit(true, true, false, true);
        emit StakeClaimed(eventId, participant, stakeAmount);

        // Call the claimParticipantStake function
        _hubUp.claimParticipantStake(eventId, participant, eventCode);

        // Assert that the participant's balance has increased by the stake amount
        uint256 finalParticipantBalance = _token.balanceOf(participant);
        assertEq(
            finalParticipantBalance,
            initialParticipantBalance + stakeAmount
        );

        (, , , , , , , , uint256 unstakedParticipantCount, , , , ) = _hubUp
            .events(0);
        assertEq(unstakedParticipantCount, 1);
    }

    function testClaimHostPayment() public {
        // Step 1: Create the event and have two participants join
        address participant1 = testJoinEvent(); // First participant joins

        console.log(
            "contract balance before participant1",
            _token.balanceOf(address(_hubUp))
        );

        testJoinEvent(); // Second participant joins

        console.log(
            "contract balance before participant2",
            _token.balanceOf(address(_hubUp))
        );

        uint256 eventId = 0; // Assuming the first event created has ID 0

        // Step 2: Have one participant claim their stake
        (, , , , , , , , , , , , string memory eventCode) = _hubUp.events(0);

        // Prank the call from the first participant to claim their stake
        vm.prank(participant1);

        console.log(
            "participant balance before claim",
            _token.balanceOf(participant1)
        );

        console.log(
            "contract balance before claim",
            _token.balanceOf(address(_hubUp))
        );

        _hubUp.claimParticipantStake(eventId, participant1, eventCode);

        // Step 3: Advance time to allow the host to claim payment
        vm.warp(endTime + 24 hours + 1);

        // Record the initial balance of the host
        uint256 initialHostBalance = _token.balanceOf(_host);

        // Calculate the expected total amount the host should receive
        uint256 expectedTotalAmount = (price * 2) + // Payment from 2 participants
            (stakeAmount * (2 - 1)) + // Only one participant's stake remains (after one unstaked)
            ((stakeAmount * maxParticipants) / 2); // Host's original stake

        // Expect the PaymentClaimed event to be emitted
        vm.expectEmit(true, true, false, true);
        emit PaymentClaimed(eventId, _host, expectedTotalAmount);

        // Prank the call from the host address to claim the payment
        vm.prank(_host);

        // Call the claimHostPayment function
        _hubUp.claimHostPayment(eventId);

        // Assert that the host's balance has increased by the expected amount
        uint256 finalHostBalance = _token.balanceOf(_host);
        assertEq(finalHostBalance, initialHostBalance + expectedTotalAmount);
    }
}
