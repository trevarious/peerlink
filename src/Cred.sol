// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "../node_modules/@openzeppelin/contracts/token/ERC20/ERC20.sol";

error Cred__OnlyPeerLinkCanCallThisFunction();
error Cred__PeerLinkAddressNotSet();

contract Cred is ERC20 {
    address public peerLinkAddress;
    bool public isPeerLinkAddressSet;

    event Cred__Mint(address, uint256);
    event Cred__Burn(address, uint256);

    constructor() ERC20("CRED", "CRED") {
        _update(address(0), msg.sender, 100 ether);
    }

    function mintCred(
        address to,
        uint256 amount
    ) external whenInitialized onlyPeerLink {
        _update(address(0), to, amount);
        emit Cred__Mint(to, amount);
    }

    function burnCred(
        address to,
        uint256 amount
    ) external whenInitialized onlyPeerLink {
        _update(to, address(0), amount);
        emit Cred__Burn(to, amount);
    }

    function initialize(address peerLink) external {
        require(!isPeerLinkAddressSet);
        peerLinkAddress = peerLink;
        isPeerLinkAddressSet = true;
    }

    modifier onlyPeerLink() {
        if (msg.sender != peerLinkAddress) {
            revert Cred__OnlyPeerLinkCanCallThisFunction();
        }
        _;
    }
    modifier whenInitialized() {
        if (!isPeerLinkAddressSet) {
            revert Cred__PeerLinkAddressNotSet();
        }
        _;
    }
}
