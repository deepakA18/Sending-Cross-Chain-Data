// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import { OAppReceiver, Origin } from "@layerzerolabs/oapp-evm/contracts/oapp/OAppReceiver.sol";
import { OAppSender, MessagingFee } from "@layerzerolabs/oapp-evm/contracts/oapp/OAppSender.sol";  // Correct import for MessagingFee
import { OptionsBuilder } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import { OAppCore } from "@layerzerolabs/oapp-evm/contracts/oapp/OAppCore.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract CrossChainOApp is OAppReceiver, OAppSender {
    using OptionsBuilder for bytes;

    // Store received data for demonstration purposes.
    string public receivedTokenName = "Nothing received yet";
    uint256 public receivedTokenAmount;

    // Define options for LayerZero messaging (e.g., gas options).
    bytes _options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(50000, 0);

    /// @notice Event emitted when a message is received.
    event MessageReceived(string tokenName, uint256 tokenAmount, uint32 senderEid, bytes32 sender, uint64 nonce);

    /// @notice Event emitted when a message is sent.
    event MessageSent(string message, uint32 dstEid);

    /**
     * @notice Initializes the contract with the source and destination chain's endpoint addresses.
     * @param _endpoint The endpoint address for LayerZero.
     */
    constructor(address _endpoint) OAppCore(_endpoint, msg.sender) Ownable(msg.sender) {}

    /**
     * @dev Called when a message is received through LayerZero. 
     * This function overrides the _lzReceive function from OAppReceiver.
     * @param _origin A struct containing information about where the packet came from.
     * @param message Encoded message containing tokenName and tokenAmount.
     */
    function _lzReceive(
        Origin calldata _origin,
        bytes32, // Removed the unused _guid parameter
        bytes calldata message,
        address, // Removed the unused executor parameter
        bytes calldata // Removed the unused _extraData parameter
    ) internal override {
        // Decode the message containing tokenName and tokenAmount
        (string memory tokenName, uint256 tokenAmount) = abi.decode(message, (string, uint256));
        
        // Update the contract state with the received data
        receivedTokenName = tokenName;
        receivedTokenAmount = tokenAmount;
        
        // Emit the MessageReceived event with details about the received message
        emit MessageReceived(tokenName, tokenAmount, _origin.srcEid, _origin.sender, _origin.nonce);
    }

    /**
     * @dev Sends a message to a destination chain after quoting the gas needed.
     * @param _dstEid Destination chain's endpoint ID.
     * @param _tokenName Token name (or address).
     * @param _tokenAmount Amount of tokens to buy.
     */
    function sendTokenPurchaseDetails(uint32 _dstEid, string memory _tokenName, uint256 _tokenAmount) external payable {
        // Construct the message
        string memory _message = string(abi.encodePacked("Purchase ", _tokenAmount, " of ", _tokenName));
        bytes memory _encodedMessage = abi.encode(_tokenName, _tokenAmount);
        
        // Quote the gas fee for sending the message
        MessagingFee memory gasQuote = quote(_dstEid, _tokenName, _tokenAmount, false);
        
        // Ensure the caller has provided enough gas fee
        require(msg.value >= gasQuote.nativeFee, "Insufficient gas fee for message sending.");

        // Send the message using the quoted gas fee
        _lzSend(
            _dstEid,
            _encodedMessage,
            _options,
            MessagingFee(gasQuote.nativeFee, 0),  // Fee in native gas
            payable(msg.sender)  // Refund address in case of failure
        );

        // Emit the MessageSent event
        emit MessageSent(_message, _dstEid);
    }

    /**
     * @dev Quotes the gas needed for sending a message to the destination chain.
     * @param _dstEid Destination chain's endpoint ID.
     * @param _tokenName Token name.
     * @param _tokenAmount Amount of tokens.
     * @param _payInLzToken Whether to return the fee in ZRO token.
     * @return fee The estimated fee for the transaction.
     */
    function quote(
        uint32 _dstEid,
        string memory _tokenName,
        uint256 _tokenAmount,
        bool _payInLzToken
    ) public view returns (MessagingFee memory fee) {
        bytes memory payload = abi.encode(_tokenName, _tokenAmount);
        fee = _quote(_dstEid, payload, _options, _payInLzToken);
    }

    /**
     * @notice Override the oAppVersion function to avoid conflict.
     * This function combines versions from both OAppReceiver and OAppSender.
     * @return senderVersion The sender version.
     * @return receiverVersion The receiver version.
     */
    function oAppVersion() public view override(OAppReceiver, OAppSender) returns (uint64 senderVersion, uint64 receiverVersion) {
        (senderVersion, receiverVersion) = OAppSender.oAppVersion(); // Use OAppSender for both
    }

    /**
     * @dev Converts an address to a bytes32 value.
     * @param _addr The address to convert.
     * @return The bytes32 representation of the address.
     */
    function addressToBytes32(address _addr) public pure returns (bytes32) {
        return bytes32(uint256(uint160(_addr)));
    }

    /**
     * @dev Converts bytes32 to an address.
     * @param _b The bytes32 value to convert.
     * @return The address representation of bytes32.
     */
    function bytes32ToAddress(bytes32 _b) public pure returns (address) {
        return address(uint160(uint256(_b)));
    }
}
