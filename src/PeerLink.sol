// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../node_modules/@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "../node_modules/@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../node_modules/@openzeppelin/contracts/interfaces/IERC20.sol";
import "../node_modules/@openzeppelin/contracts/utils/Strings.sol";
import "../node_modules/@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./Cred.sol";

error PeerLink__AccountAlreadyActive();
error PeerlLink__RequestAlreadySent();
error PeerLink__CannotCallToYourself();
error PeerLink__MustBeAccountHolder();
error PeerLink__MustBeFriends();
error PeerLink__AlreadyFriends();
error PeerLink__AddressIsNotSmartContract(address);
error PeerLink__NonERC20Token(address);
error PeerLink__TransferFailed();
error PeerLink__ValueMustExceedZero();
error PeerLink__InvalidParams();
error PeerLink__NoAccountFound(address account);
error PeerLink__NoRequestFound();
error PeerLink__NoTokenFound();
error PeerLink__InsufficientBalance(
    address token,
    uint256 balance,
    uint256 needed
);

contract PeerLink is ERC721, ReentrancyGuard {
    struct Bio {
        string name;
        string aboutMe;
    }
    struct UserInfo {
        Bio info;
        uint256 friendsCount;
        uint256 reputation;
    }
    struct Message {
        string senderName; // Changed from address to string
        string content;
        uint256 timestamp;
        uint256 polSent;
        address token;
        uint256 tokensSent;
    }
    struct RequestInfo {
        address requesterAddress;
        string requesterName;
        uint256 timestamp;
    }
    Cred cred;

    uint256 private constant FRIEND_REQUEST_CRED_REWARD = 5;
    uint256 private constant ACCEPT_FRIEND_CRED_REWARD = 10;
    uint256 private constant SEND_MESSAGE_CRED_REWARD = 3;
    uint256 private constant UPDATE_PROFILE_CRED_COST = 20;
    uint256 public constant NEW_ACCOUNT_CRED_REWARD = 100;

    mapping(uint256 => UserInfo) public userInfos;
    mapping(address => uint256) public userIds;

    mapping(address => address[]) public friends;
    mapping(address => mapping(address => bool)) public friendRequests;
    mapping(address => mapping(address => uint256))
        public friendRequestsTimestamp;
    mapping(address => address[]) public requesters;

    mapping(bytes32 => Message[]) private messageThreads;

    mapping(address => uint256) polDeposits;
    mapping(address => mapping(address => uint256)) public tokenDeposits;

    uint256 private _currentTokenId;

    event MessageSent(
        address indexed from,
        address indexed to,
        string content,
        uint256 polSent
    );
    event MessageSentWithTokens(
        address indexed from,
        address indexed to,
        string content,
        uint256 polSent,
        address tokenAddress,
        uint256 tokensSent
    );
    event RequestSent(address, address);
    event RequestAccepted(address, address);
    event RequestDenied(address, address);
    event TokenDeposit(address, address, uint256);
    event POLDeposit(address, uint256);
    event TokenWithdraw(address account, address token, uint256 amount);
    event POLWithdraw(address, uint256);
    event Debug(string jsonString);

    constructor() payable ERC721("PeerLink", "PLNFT") {
        cred = new Cred();
        cred.initialize(address(this));
    }

    receive() external payable {}

    function mintUser(
        address to,
        string memory name,
        string memory aboutMe
    ) external {
        require(userIds[to] == 0, PeerLink__AccountAlreadyActive());

        _currentTokenId++;
        uint256 tokenId = _currentTokenId;
        _mint(to, tokenId);

        userInfos[tokenId] = UserInfo({
            info: Bio({name: name, aboutMe: aboutMe}),
            friendsCount: 0,
            reputation: 0
        });

        userIds[to] = tokenId;
        cred.mintCred(to, NEW_ACCOUNT_CRED_REWARD);
    }

    function getUserInfo(
        address addr
    ) public view MustBeAccountHolder(msg.sender) returns (UserInfo memory) {
        require(userIds[addr] != 0, PeerLink__NoAccountFound(addr));
        uint256 id = userIds[addr];
        return userInfos[id];
    }

    function tokenURI(
        uint256 tokenId
    ) public view override returns (string memory) {
        UserInfo memory user = userInfos[tokenId];

        string memory json = string(
            abi.encodePacked(
                '{"name":"',
                user.info.name,
                '",',
                '"description":"',
                user.info.aboutMe,
                '",',
                '"attributes":[{"trait_type":"Friends Count","value":',
                Strings.toString(user.friendsCount),
                '},{"trait_type":"Reputation","value":',
                Strings.toString(user.reputation),
                "}]}"
            )
        );

        return json;
    }

    function sendFriendRequest(address to) external {
        require(userIds[msg.sender] != 0, PeerLink__NoAccountFound(msg.sender));
        require(userIds[to] != 0, PeerLink__NoAccountFound(to));
        require(msg.sender != to, PeerLink__CannotCallToYourself());
        require(
            !friendRequests[to][msg.sender],
            PeerlLink__RequestAlreadySent()
        );
        require(!isFriend(msg.sender, to), PeerLink__AlreadyFriends());

        friendRequests[to][msg.sender] = true;
        friendRequestsTimestamp[to][msg.sender] = block.timestamp;
        requesters[to].push(msg.sender);

        cred.mintCred(to, FRIEND_REQUEST_CRED_REWARD);

        emit RequestSent(msg.sender, to);
    }

    function isRequestSent(address to) external view returns (bool) {
        require(userIds[msg.sender] != 0, PeerLink__NoAccountFound(msg.sender));
        require(userIds[to] != 0, PeerLink__NoAccountFound(to));
        require(msg.sender != to, PeerLink__CannotCallToYourself());
        return friendRequests[to][msg.sender];
    }

    function handleFriendRequest(address from, bool accept) external {
        require(friendRequests[msg.sender][from], PeerLink__NoRequestFound());

        if (accept) {
            require(!isFriend(msg.sender, from), PeerLink__AlreadyFriends());

            uint256 userId = userIds[msg.sender];
            uint256 fromUserId = userIds[from];

            friends[msg.sender].push(from);
            userInfos[userId].friendsCount++;

            friends[from].push(msg.sender);
            userInfos[fromUserId].friendsCount++;

            cred.mintCred(msg.sender, ACCEPT_FRIEND_CRED_REWARD);
            cred.mintCred(from, ACCEPT_FRIEND_CRED_REWARD);

            emit RequestAccepted(from, msg.sender);
        } else {
            emit RequestDenied(from, msg.sender);
        }

        // Common logic for both accept and decline
        delete friendRequests[msg.sender][from];
        delete friendRequestsTimestamp[msg.sender][from];
        removeRequester(msg.sender, from);
    }

    function getIncomingRequests()
        external
        view
        returns (RequestInfo[] memory)
    {
        address[] memory requesterAddresses = requesters[msg.sender];
        uint256 requestCount = requesterAddresses.length;

        RequestInfo[] memory requests = new RequestInfo[](requestCount);

        for (uint256 i = 0; i < requestCount; i++) {
            address requesterAddress = requesterAddresses[i];
            uint256 requesterId = userIds[requesterAddress];

            requests[i] = RequestInfo({
                requesterAddress: requesterAddress,
                requesterName: userInfos[requesterId].info.name,
                timestamp: friendRequestsTimestamp[msg.sender][requesterAddress]
            });
        }

        return requests;
    }

    function removeRequester(address user, address requesterToRemove) internal {
        address[] storage userRequesters = requesters[user];
        for (uint i = 0; i < userRequesters.length; i++) {
            if (userRequesters[i] == requesterToRemove) {
                userRequesters[i] = userRequesters[userRequesters.length - 1];
                userRequesters.pop();
                break;
            }
        }
    }

    function isFriend(
        address user1,
        address user2
    ) internal view returns (bool) {
        address[] storage tempFriends = friends[user1];
        for (uint256 i = 0; i < tempFriends.length; i++) {
            if (tempFriends[i] == user2) {
                return true;
            }
        }
        return false;
    }

    function getFriends() external view returns (address[] memory) {
        return friends[msg.sender];
    }

    function getFriendsInfo()
        external
        view
        returns (address[] memory, Bio[] memory)
    {
        address[] memory tempFriends = friends[msg.sender]; // Change to memory
        uint256 friendCount = tempFriends.length;
        Bio[] memory friendsInfo = new Bio[](friendCount);

        for (uint256 i = 0; i < friendCount; i++) {
            friendsInfo[i] = userInfos[userIds[tempFriends[i]]].info; // Minimize read operations
        }

        return (tempFriends, friendsInfo);
    }

    function updateName(
        uint256 tokenId,
        string memory newName
    ) external MustBeAccountHolder(msg.sender) {
        userInfos[tokenId].info.name = newName;
    }

    function updateBio(
        uint256 tokenId,
        string memory newBio
    ) external MustBeAccountHolder(msg.sender) {
        userInfos[tokenId].info.aboutMe = newBio;
    }

    function sendMessage(
        address to,
        string memory content
    ) external payable MustBeFriends(to, msg.sender) {
        require(userIds[msg.sender] != 0, PeerLink__NoAccountFound(msg.sender));
        require(userIds[to] != 0, PeerLink__NoAccountFound(to));
        bytes32 threadId = getThreadId(msg.sender, to);
        string memory senderName = userInfos[userIds[msg.sender]].info.name;
        Message memory newMessage = Message({
            senderName: senderName,
            content: content,
            timestamp: block.timestamp,
            polSent: msg.value,
            token: address(0),
            tokensSent: 0
        });
        messageThreads[threadId].push(newMessage);
        if (msg.value > 0) {
            payable(to).transfer(msg.value);
        }

        emit MessageSent(msg.sender, to, content, msg.value);
    }

    function sendMessage(
        address to,
        string memory content,
        address token,
        uint256 amount
    ) external payable MustBeFriends(to, msg.sender) {
        require(userIds[msg.sender] != 0, PeerLink__NoAccountFound(msg.sender));
        require(userIds[to] != 0, PeerLink__NoAccountFound(to));
        bytes32 threadId = getThreadId(msg.sender, to);
        string memory senderName = userInfos[userIds[msg.sender]].info.name; // Get sender's name
        Message memory newMessage = Message({
            senderName: senderName, // Store sender's name
            content: content,
            timestamp: block.timestamp,
            polSent: msg.value,
            token: token,
            tokensSent: amount
        });
        messageThreads[threadId].push(newMessage);
        if (msg.value > 0) {
            payable(to).transfer(msg.value);
        }
        _sendToken(token, to, amount);
        emit MessageSentWithTokens(
            msg.sender,
            to,
            content,
            msg.value,
            token,
            amount
        );
    }

    function getMessages(
        address friend
    ) external view returns (Message[] memory) {
        require(isFriend(msg.sender, friend), PeerLink__MustBeFriends());
        bytes32 threadId = getThreadId(msg.sender, friend);
        return messageThreads[threadId];
    }

    function getThreadId(
        address user1,
        address user2
    ) private pure returns (bytes32) {
        return
            user1 < user2
                ? keccak256(abi.encodePacked(user1, user2))
                : keccak256(abi.encodePacked(user2, user1));
    }

    function depositPOL() external payable MustBeNonZero(msg.value) {
        payable(address(this)).transfer(msg.value);
        polDeposits[msg.sender] += msg.value;
    }

    function depositToken(
        address token,
        uint256 amount
    ) external MustBeNonZero(amount) nonReentrant {
        require(token != address(0), PeerLink__NoTokenFound());
        require(isContract(token), PeerLink__AddressIsNotSmartContract(token));
        require(token != address(cred), "Can't depoist cred");

        (bool success, ) = token.call(abi.encodeWithSignature("totalSupply()"));
        require(success, PeerLink__NonERC20Token(token));

        tokenDeposits[msg.sender][token] += amount;

        success = IERC20(token).transferFrom(msg.sender, address(this), amount);
        require(success, PeerLink__TransferFailed());

        emit TokenDeposit(msg.sender, token, amount);
    }

    function withdrawPOL(uint256 amount) external MustBeNonZero(amount) {
        require(
            polDeposits[msg.sender] >= amount,
            PeerLink__InsufficientBalance(
                address(0),
                polDeposits[msg.sender],
                amount
            )
        );
        payable(msg.sender).transfer(amount);
        polDeposits[msg.sender] -= amount;
        emit POLWithdraw(msg.sender, amount);
    }

    function withdrawToken(
        address token,
        uint256 amount
    ) external MustBeNonZero(amount) {
        require(
            tokenDeposits[msg.sender][token] >= amount,
            PeerLink__InsufficientBalance(
                token,
                tokenDeposits[msg.sender][token],
                amount
            )
        );
        tokenDeposits[msg.sender][token] -= amount;
        bool success = IERC20(token).transfer(msg.sender, amount);
        require(success, PeerLink__TransferFailed());
        emit TokenWithdraw(msg.sender, token, amount);
    }

    function _sendToken(address token, address to, uint256 amount) private {
        require(
            token != address(0) &&
                to != address(0) &&
                amount > 0 &&
                tokenDeposits[msg.sender][token] >= amount,
            PeerLink__InvalidParams()
        );
        tokenDeposits[msg.sender][token] -= amount;
        tokenDeposits[to][token] += amount;
    }

    function tokenBalances(
        address token,
        address account
    ) public view returns (uint256) {
        return tokenDeposits[account][token];
    }

    function polBalance(address account) public view returns (uint256) {
        return polDeposits[account];
    }

    function credBalance(address account) public view returns (uint256) {
        return IERC20(credAddress()).balanceOf(account);
    }

    function credAddress() public view returns (address) {
        return address(cred);
    }

    function increaseReputation(uint256 amount) public {
        uint256 currentBalance = IERC20(credAddress()).balanceOf(msg.sender);
        require(userIds[msg.sender] != 0, PeerLink__NoAccountFound(msg.sender));
        uint256 tokenId = userIds[msg.sender];
        require(
            currentBalance >= amount,
            PeerLink__InsufficientBalance(credAddress(), currentBalance, amount)
        );
        userInfos[tokenId].reputation += amount;
    }

    // Helper function to check if an address is a contract
    function isContract(address account) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(account)
        }
        return size > 0;
    }

    modifier MustBeFriends(address to, address from) {
        require(isFriend(to, from), PeerLink__MustBeFriends());
        _;
    }
    modifier MustBeAccountHolder(address inQuestion) {
        require(msg.sender == inQuestion, PeerLink__MustBeAccountHolder());
        _;
    }
    modifier MustBeNonZero(uint256 amount) {
        require(amount > 0, PeerLink__ValueMustExceedZero());
        _;
    }
}
