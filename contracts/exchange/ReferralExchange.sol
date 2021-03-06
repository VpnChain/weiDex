pragma solidity 0.4.24;

import "./Exchange.sol";

contract ReferralExchange is Exchange {

    uint256 public referralFeeRate;

    mapping(address => address) public referrals;

    constructor(
        uint256 _referralFeeRate
    )
        public
    {
        referralFeeRate = _referralFeeRate;
    }

    event ReferralBalanceUpdated(
        address refererAddress,
        address referralAddress,
        address tokenAddress,
        uint256 feeAmount,
        uint256 referralFeeAmount
    );

    event ReferralDeposit(
        address token,
        address indexed user,
        address indexed referrer,
        uint256 amount,
        uint256 balance
    );

    /**
    * @dev Deposit Ethers with a given referrer address
    * @param _referrer address of the referrer
    */
    function depositEthers(address _referrer)
        external
        payable
    {
        address user = msg.sender;

        require(
            0x0 == referrals[user],
            "This user already have a referrer."
        );

        super._depositEthers(user);
        referrals[user] = _referrer;
        emit ReferralDeposit(ETH, user, _referrer, msg.value, balances[ETH][user]);
    }

    /**
    * @dev Deposit Tokens with a given referrer address
    * @param _referrer address of the referrer
    */
    function depositTokens(
        address _tokenAddress,
        uint256 _amount,
        address _referrer
    )
        external
    {
        address user = msg.sender;

        require(
            0x0 == referrals[user],
            "This user already have a referrer."
        );

        super._depositTokens(_tokenAddress, _amount, user);
        referrals[user] = _referrer;
        emit ReferralDeposit(_tokenAddress, user, _referrer, _amount, balances[_tokenAddress][user]);
    }

    /**
    * @dev Update the referral fee rate,
    * i.e. the rate of the fee that will be accounted to the referrer
    * @param _referralFeeRate uint256 amount of fee going to the referrer
    */
    function setReferralFee(uint256 _referralFeeRate)
        external
        onlyOwner
    {
        referralFeeRate = _referralFeeRate;
    }

    /**
    * @dev Return the feeAccount address if user doesn't have referrer
    * @param _user address user whom referrer is being checked.
    * @return address of user's referrer.
    */
    function getReferrer(address _user)
        internal
        view
        returns(address referrer)
    {
        return referrals[_user] != address(0x0) ? referrals[_user] : feeAccount;
    }

}
