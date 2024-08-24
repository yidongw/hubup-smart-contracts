import "forge-std/console.sol";

// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

interface IERC20 {
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);

    function transfer(
        address recipient,
        uint256 amount
    ) external returns (bool);

    function balanceOf(address account) external view returns (uint256);
}

contract HubUp {
    struct Event {
        address host;
        uint256 startTime;
        uint256 endTime;
        uint256 price;
        uint256 stakeAmount;
        uint256 minParticipants;
        uint256 maxParticipants;
        uint256 participantCount; // Current number of participants attending
        uint256 unstakedParticipantCount; // Current number of participants attending
        uint256 totalParticipantsJoined; // Total number of participants who have ever joined
        bool isFinalized;
        bool isPaymentBlocked;
        string eventCode;
        mapping(address => bool) participants;
        mapping(address => bool) hasLeft;
    }

    address public owner;
    IERC20 public usdcToken;

    uint256 public nextEventId;
    mapping(uint256 => Event) public events;

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

    modifier onlyOwner() {
        require(msg.sender == owner, "Not the contract owner");
        _;
    }

    modifier onlyHost(uint256 eventId) {
        require(events[eventId].host == msg.sender, "Not the event host");
        _;
    }

    constructor(address _usdcToken) {
        owner = msg.sender;
        usdcToken = IERC20(_usdcToken);
    }

    function createEvent(
        uint256 startTime,
        uint256 endTime,
        uint256 price,
        uint256 stakeAmount,
        uint256 minParticipants,
        uint256 maxParticipants
    ) external {
        require(
            startTime >= block.timestamp,
            "Start time cannot be earlier than current time"
        );
        require(
            endTime > startTime,
            "End time cannot be earlier than start time"
        );
        require(
            endTime <= startTime + 24 hours,
            "Event duration cannot exceed 24 hours"
        );

        console.log("Creating event with start time:", startTime);
        console.log("Host address:", msg.sender);

        // Host must deposit stakeAmount * maxParticipants / 2
        uint256 requiredStake = (stakeAmount * maxParticipants) / 2;
        require(
            usdcToken.transferFrom(msg.sender, address(this), requiredStake),
            "Stake deposit failed"
        );

        uint256 eventId = nextEventId++;

        console.log("eventId:", eventId);

        Event storage newEvent = events[eventId];
        newEvent.host = msg.sender;
        newEvent.startTime = startTime;
        newEvent.endTime = endTime;
        newEvent.price = price;
        newEvent.stakeAmount = stakeAmount;
        newEvent.minParticipants = minParticipants;
        newEvent.maxParticipants = maxParticipants;
        newEvent.isFinalized = false;
        newEvent.isPaymentBlocked = false;
        newEvent.eventCode = generateEventCode();

        console.log("eventCode:", newEvent.eventCode);

        emit EventCreated(eventId, msg.sender, newEvent.eventCode);
    }

    function joinEvent(uint256 eventId) external {
        Event storage eventDetails = events[eventId];
        require(
            eventDetails.participantCount < eventDetails.maxParticipants,
            "Event is full"
        );
        require(
            !eventDetails.participants[msg.sender],
            "Already joined this event"
        );

        uint256 totalCost = eventDetails.price + eventDetails.stakeAmount;
        require(
            usdcToken.transferFrom(msg.sender, address(this), totalCost),
            "Payment failed"
        );

        eventDetails.participants[msg.sender] = true;
        eventDetails.participantCount += 1;
        eventDetails.totalParticipantsJoined += 1;

        if (
            !eventDetails.isFinalized &&
            eventDetails.participantCount >= eventDetails.minParticipants
        ) {
            eventDetails.isFinalized = true;
            emit EventFormalized(eventId);
        }

        emit ParticipantJoined(eventId, msg.sender);
    }

    function leaveEvent(
        uint256 eventId,
        address participant // string memory code
    ) external {
        Event storage eventDetails = events[eventId];
        require(eventDetails.participants[participant], "Not a participant");
        require(!eventDetails.hasLeft[participant], "Already marked as left");

        // Only the host or the participant themselves can mark as left
        require(
            msg.sender == eventDetails.host || msg.sender == participant,
            "Only the host or the participant can mark as left"
        );

        eventDetails.participantCount -= 1;
        eventDetails.hasLeft[participant] = true;

        emit ParticipantLeft(eventId, participant);
    }

    function claimParticipantStake(
        uint256 eventId,
        address participant,
        string memory code
    ) external {
        Event storage eventDetails = events[eventId];
        require(eventDetails.participants[participant], "Not a participant");
        require(
            keccak256(abi.encodePacked(code)) ==
                keccak256(abi.encodePacked(eventDetails.eventCode)),
            "Incorrect code"
        );

        // Transfer the stake back to the participant
        require(
            usdcToken.transfer(participant, eventDetails.stakeAmount),
            "Stake refund failed"
        );
        eventDetails.unstakedParticipantCount += 1;

        emit StakeClaimed(eventId, participant, eventDetails.stakeAmount);
    }

    function claimHostPayment(uint256 eventId) external onlyHost(eventId) {
        Event storage eventDetails = events[eventId];
        require(
            block.timestamp > eventDetails.endTime + 24 hours,
            "Claim period not started"
        );
        require(!eventDetails.isPaymentBlocked, "Host payment is blocked");

        // Calculate the total amount the host can claim
        uint256 totalAmount = (eventDetails.price *
            eventDetails.totalParticipantsJoined) +
            (eventDetails.stakeAmount *
                (eventDetails.totalParticipantsJoined -
                    eventDetails.unstakedParticipantCount)) +
            ((eventDetails.stakeAmount * eventDetails.maxParticipants) / 2);

        require(
            usdcToken.transfer(eventDetails.host, totalAmount),
            "Payment claim failed"
        );

        emit PaymentClaimed(eventId, eventDetails.host, totalAmount);
    }

    function blockEventPayment(uint256 eventId) external onlyOwner {
        events[eventId].isPaymentBlocked = true;
        emit EventPaymentBlocked(eventId);
    }

    function unblockEventPayment(uint256 eventId) external onlyOwner {
        events[eventId].isPaymentBlocked = false;
        emit EventPaymentUnblocked(eventId);
    }

    function takeHostPaymentByOwner(uint256 eventId) external onlyOwner {
        Event storage eventDetails = events[eventId];
        require(eventDetails.isPaymentBlocked, "Host payment is not blocked");

        // Calculate the total amount the host can claim
        uint256 totalAmount = (eventDetails.price *
            eventDetails.totalParticipantsJoined) +
            (eventDetails.stakeAmount *
                (eventDetails.totalParticipantsJoined -
                    eventDetails.unstakedParticipantCount)) +
            ((eventDetails.stakeAmount * eventDetails.maxParticipants) / 2);

        require(
            usdcToken.transfer(owner, totalAmount),
            "Payment transfer failed"
        );
    }

    function generateEventCode() private view returns (string memory) {
        console.log("block.timestamp:", block.timestamp);

        uint256 randomNum = uint256(
            keccak256(abi.encodePacked(block.timestamp, msg.sender))
        ) % 1000000;
        return toString(randomNum);
    }

    function toString(uint256 value) private pure returns (string memory) {
        // Convert uint256 to string
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
}
