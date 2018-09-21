pragma solidity 0.4.24;

import "../utils/Ownable.sol";
import "../utils/Math.sol";
import "../utils/OrderLib.sol";
import "../utils/Token.sol";

contract Exchange is Ownable {

    using Math for uint256;

    using OrderLib for OrderLib.Order;

    uint256 public feeRate;

    mapping(address => mapping(address => uint256)) public balances;

    mapping(bytes32 => uint256) public filledAmounts;

    address constant public ETH = address(0x0);

    address public feeAccount;

    uint8 constant public VERSION = 0;


    constructor(
        address _feeAccount,
        uint256 _feeRate
    )
    public
    {
        feeAccount = _feeAccount;
        feeRate = _feeRate;
    }

    enum ErrorCode {
        INSUFFICIENT_MAKER_BALANCE,
        INSUFFICIENT_TAKER_BALANCE,
        INSUFFICIENT_ORDER_AMOUNT
    }

    event Deposit(
        address indexed tokenAddress,
        address indexed user,
        uint256 amount,
        uint256 balance
    );

    event Withdraw(
        address indexed tokenAddress,
        address indexed user,
        uint256 amount,
        uint256 balance
    );

    event CancelOrder(
        address indexed makerBuyToken,
        address indexed makerSellToken,
        address indexed maker,
        bytes32 orderHash,
        uint256 nonce
    );

    event TakeOrder(
        address indexed maker,
        address taker,
        address indexed makerBuyToken,
        address indexed makerSellToken,
        uint256 takerGivenAmount,
        uint256 takerReceivedAmount,
        bytes32 orderHash,
        uint256 nonce
    );

    event Error(
        uint8 eventId,
        bytes32 orderHash
    );

    /**
    * @dev Owner can set the exchange fee
    * @param _feeRate uint256 new fee rate
    */
    function setFee(uint256 _feeRate)
        external
        onlyOwner
    {
        feeRate = _feeRate;
    }

    /**
    * @dev Allows user to deposit Ethers in the exchange contract.
    * Only the respected user can withdraw these Ethers.
    */
    function depositEthers() external payable
    {
        _depositEthers();
        emit Deposit(ETH, msg.sender, msg.value, balances[ETH][msg.sender]);
    }

    /**
    * @dev Allows user to deposit Tokens in the exchange contract.
    * Only the respected user can withdraw these tokens.
    * @param _tokenAddress address representing the token contract address.
    * @param _amount uint256 representing the token amount to be deposited.
    */
    function depositTokens(
        address _tokenAddress,
        uint256 _amount
    )
        external
    {
        _depositTokens(_tokenAddress, _amount);
        emit Deposit(_tokenAddress, msg.sender, _amount, balances[_tokenAddress][msg.sender]);
    }

    /**
    * @dev Internal version of deposit Ethers.
    */
    function _depositEthers() internal
    {
        balances[ETH][msg.sender] = balances[ETH][msg.sender].add(msg.value);
    }

    /**
    * @dev Internal version of deposit Tokens.
    */
    function _depositTokens(
        address _tokenAddress,
        uint256 _amount
    )
        internal
    {
        balances[_tokenAddress][msg.sender] = balances[_tokenAddress][msg.sender].add(_amount);

        require(
            Token(_tokenAddress).transferFrom(msg.sender, this, _amount),
            "Token transfer is not successfull (maybe you haven't used approve first?)"
        );
    }

    /**
    * @dev Allows user to withdraw Ethers from the exchange contract.
    * Throws if the user balance is lower than the requested amount.
    * @param _amount uint256 representing the amount to be withdrawn.
    */
    function withdrawEthers(uint256 _amount) external
    {
        require(
            balances[ETH][msg.sender] >= _amount,
            "Not enough funds to withdraw."
        );

        balances[ETH][msg.sender] = balances[ETH][msg.sender].sub(_amount);

        msg.sender.transfer(_amount);

        emit Withdraw(ETH, msg.sender, _amount, balances[ETH][msg.sender]);
    }

    /**
    * @dev Allows user to withdraw specific Token from the exchange contract.
    * Throws if the user balance is lower than the requested amount.
    * @param _tokenAddress address representing the token contract address.
    * @param _amount uint256 representing the amount to be withdrawn.
    */
    function withdrawTokens(
        address _tokenAddress,
        uint256 _amount
    )
        external
    {
        require(
            balances[_tokenAddress][msg.sender] >= _amount,
            "Not enough funds to withdraw."
        );

        balances[_tokenAddress][msg.sender] = balances[_tokenAddress][msg.sender].sub(_amount);

        require(
            Token(_tokenAddress).transfer(msg.sender, _amount),
            "Token transfer is not successfull."
        );

        emit Withdraw(_tokenAddress, msg.sender, _amount, balances[_tokenAddress][msg.sender]);
    }

    /**
    * @dev Common take order implementation
    * @param _order OrderLib.Order memory - order info
    * @param _takerSellAmount uint256 - amount being given by the taker
    * @param _v uint8 part of the signature
    * @param _r bytes32 part of the signature (from 0 to 32 bytes)
    * @param _s bytes32 part of the signature (from 32 to 64 bytes)
    */
    function takeOrder(
        OrderLib.Order memory _order,
        uint256 _takerSellAmount,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    )
        internal
        returns (uint256)
    {
        bytes32 orderHash = _order.createHash();

        require(
            ecrecover(keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", orderHash)), _v, _r, _s) == _order.maker,
            "Order maker is invalid."
        );

        if(balances[_order.makerBuyToken][msg.sender] < _takerSellAmount) {
            emit Error(uint8(ErrorCode.INSUFFICIENT_TAKER_BALANCE), orderHash);
            return 0;
        }

        uint256 receivedAmount = (_order.makerSellAmount.mul(_takerSellAmount)).div(_order.makerBuyAmount);

        if(balances[_order.makerSellToken][_order.maker] < receivedAmount) {
            emit Error(uint8(ErrorCode.INSUFFICIENT_MAKER_BALANCE), orderHash);
            return 0;
        }

        if(filledAmounts[orderHash].add(_takerSellAmount) > _order.makerBuyAmount) {
            emit Error(uint8(ErrorCode.INSUFFICIENT_ORDER_AMOUNT), orderHash);
            return 0;
        }

        filledAmounts[orderHash] = filledAmounts[orderHash].add(_takerSellAmount);

        balances[_order.makerBuyToken][msg.sender] = balances[_order.makerBuyToken][msg.sender].sub(_takerSellAmount);
        balances[_order.makerBuyToken][_order.maker] = balances[_order.makerBuyToken][_order.maker].add(_takerSellAmount);

        balances[_order.makerSellToken][msg.sender] = balances[_order.makerSellToken][msg.sender].add(receivedAmount);
        balances[_order.makerSellToken][_order.maker] = balances[_order.makerSellToken][_order.maker].sub(receivedAmount);

        emit TakeOrder(
            _order.maker,
            msg.sender,
            _order.makerBuyToken,
            _order.makerSellToken,
            _takerSellAmount,
            receivedAmount,
            orderHash,
            _order.nonce
        );

        return receivedAmount;
    }

    /**
    * @dev Order maker can call this function in order to cancel it.
    * What actually happens is that the order become
    * fulfilled in the "filledAmounts" mapping. Thus we avoid someone calling
    * "takeOrder" directly from the contract if the order hash is available to him.
    * @param _orderAddresses address[3]
    * @param _orderValues uint256[3]
    * @param _v uint8 parameter parsed from the signature recovery
    * @param _r bytes32 parameter parsed from the signature (from 0 to 32 bytes)
    * @param _s bytes32 parameter parsed from the signature (from 32 to 64 bytes)
    */
    function cancelOrder(
        address[3] _orderAddresses,
        uint256[3] _orderValues,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    )
        public
    {
        OrderLib.Order memory order = OrderLib.createOrder(_orderAddresses, _orderValues);
        bytes32 orderHash = order.createHash();

        require(
            ecrecover(keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", orderHash)), _v, _r, _s) == msg.sender,
            "Only order maker can cancel it."
        );

        filledAmounts[orderHash] = filledAmounts[orderHash].add(order.makerBuyAmount);

        emit CancelOrder(
            order.makerBuyToken,
            order.makerSellToken,
            msg.sender,
            orderHash,
            order.nonce
        );
    }

    /**
    * @dev Cancel multiple orders in a single transaction.
    * @param _orderAddresses address[3][]
    * @param _orderValues uint256[3][]
    * @param _v uint8[] parameter parsed from the signature recovery
    * @param _r bytes32[] parameter parsed from the signature (from 0 to 32 bytes)
    * @param _s bytes32[] parameter parsed from the signature (from 32 to 64 bytes)
    */
    function cancelMultipleOrders(
        address[3][] _orderAddresses,
        uint256[3][] _orderValues,
        uint8[] _v,
        bytes32[] _r,
        bytes32[] _s
    )
        external
    {
        for (uint256 index = 0; index < _orderAddresses.length; index++) {
            cancelOrder(
                _orderAddresses[index],
                _orderValues[index],
                _v[index],
                _r[index],
                _s[index]
            );
        }
    }

}
