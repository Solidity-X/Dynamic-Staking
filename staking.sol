// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

/*\
Created by SolidityX
Telegram: @solidityX
\*/


import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";



contract Staking {
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeMath for uint;

    IERC20 private depToken; // deposit token (LP)
    IERC20 private rewToken; // reward token
    EnumerableSet.AddressSet private stakeholders; // list of depositor addresses

    /*\
    struct that contains information about the deposit
    \*/
    struct Stake {
        uint staked;
        uint shares;
    }

    address public owner; // owner of the contract
    uint private totalStakes; // total amount of tokens deposited
    uint private totalShares; // total amount of shares issued
    bool private initialized; // if contract is initialized

    mapping(address => Stake) private stakeholderToStake; // mapping from the depositor address to his information (tokens deposited etc.)

    /*\
    function with this modifier can only be called by the owner
    \*/
    modifier onlyOwner() {
        require(msg.sender == owner, "caller not owner");
        _;
    }

    /*\
    sets important variables at deployment
    \*/
    constructor(address _depToken, address _rewToken) {
        depToken = IERC20(_depToken);
        rewToken = IERC20(_rewToken);
        owner = msg.sender;
    }

    event StakeAdded(address indexed stakeholder, uint amount, uint shares, uint timestamp); // this event emits on every deposit
    event StakeRemoved(address indexed stakeholder, uint amount, uint shares, uint reward, uint timestamp); // this event emits on every withdraw


/*//////////////////////////////////////////////‾‾‾‾‾‾‾‾‾‾\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\*\
///////////////////////////////////////////////executeables\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\
\*\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\____________/////////////////////////////////////////////*/

    /*\
    initialize all values
    amount will be locked forever
    \*/
    function initialize(uint _amount) external onlyOwner {
        require(!initialized, "already initialized!");
        require(depToken.transferFrom(msg.sender, address(this), _amount), "transfer failed!");

        stakeholderToStake[address(0x0)] = Stake({
            staked: _amount,
            shares: _amount
        });
        totalStakes = _amount;
        totalShares = _amount;
        initialized = true;
        owner = address(0x0);
        emit StakeAdded(address(0x0), _amount, _amount, block.timestamp);
    }

    /*\
    stake tokens
    \*/
    function deposit(uint _amount) external returns(bool) {
        _deposit(msg.sender, _amount);
        return true;
    }

    /*\
    withdraw function if in emergency state (no rewards)
    \*/
    function emergencyWithdraw() external returns(bool) {
        uint stake = stakeholderToStake[msg.sender].staked;
        uint shares = stakeholderToStake[msg.sender].shares;

        stakeholderToStake[msg.sender] = Stake({
            staked: 0,
            shares: 0
        });
        totalShares = totalShares.sub(shares);
        totalStakes = totalStakes.sub(stake);

        require(depToken.transfer(msg.sender, stake), "initial transfer failed!");

        stakeholders.remove(msg.sender);
        return true;
    }

    /*\
    remove staked tokens
    \*/
    function withdraw() external returns(bool){
        _withdraw(msg.sender);
        return true;
    }

    /*\
    remove staked tokens
    \*/
    function _withdraw(address _account) internal {
        require(stakeholderToStake[_account].staked > 0, "not staked!");
        uint rewards = rewardOf(_account);
        uint stake = stakeholderToStake[_account].staked;
        uint shares = stakeholderToStake[_account].shares;

        stakeholderToStake[_account] = Stake({
            staked: 0,
            shares: 0
        });
        totalShares = totalShares.sub(shares);
        totalStakes = totalStakes.sub(stake);

        require(depToken.transfer(_account, stake), "initial transfer failed!");
        require(rewToken.transfer(_account, rewards), "reward transfer failed!");

        stakeholders.remove(_account);

        emit StakeRemoved(_account, stake, shares, rewards, block.timestamp);
    }

    /*\
    stake tokens
    \*/
     function _deposit(address _account, uint _amount) private {
        require(initialized, "not initialized!");
        require(_amount > 0, "amount too small!");

        uint tbal = depToken.balanceOf(address(this)).add(rewToken.balanceOf(address(this)));
        uint shares = _amount.mul(totalShares).div(tbal);
        require(depToken.transferFrom(_account, address(this), _amount), "transfer failed!");

        stakeholders.add(_account);
        stakeholderToStake[_account] = Stake({
            staked: _amount,
            shares: shares
        });
        totalStakes = totalStakes.add(_amount);
        totalShares += shares;
        emit StakeAdded(_account, _amount, shares, block.timestamp);
    }




/*//////////////////////////////////////////////‾‾‾‾‾‾‾‾‾‾‾\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\*\
///////////////////////////////////////////////viewable/misc\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\
\*\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\_____________/////////////////////////////////////////////*/


    /*\
    ratio of token/share
    \*/
    function getRatio() public view returns(uint) {
        uint tbal = depToken.balanceOf(address(this)).add(rewToken.balanceOf(address(this)));
        return tbal.mul(1e18).div(totalShares);
    }

    /*\
    get token stake of user
    \*/
    function stakeOf(address stakeholder) public view returns (uint) {
        return stakeholderToStake[stakeholder].staked;
    }

    /*\
    get shares of user
    \*/
    function sharesOf(address stakeholder) public view returns (uint) {
        return stakeholderToStake[stakeholder].shares;
    }

    /*\
    get total amount of tokens staked
    \*/
    function getTotalStakes() external view returns (uint) {
        return totalStakes;
    }

    /*\
    get total amount of shares
    \*/ 
    function getTotalShares() external view returns (uint) {
        return totalShares;
    }

    /*\
    get total current rewards
    \*/
    function getCurrentRewards() external view returns (uint) {
        return rewToken.balanceOf(address(this));
    }

    /*\
    get list of all stakers
    \*/
    function getTotalStakeholders() public view returns (uint) {
        return stakeholders.length();
    }


    /*\
    get rewards that user received
    \*/
    function rewardOf(address stakeholder) public view returns (uint) {
        uint stakeholderStake = stakeOf(stakeholder);
        uint stakeholderShares = sharesOf(stakeholder);

        if (stakeholderShares == 0) {
            return 0;
        }

        uint stakedRatio = stakeholderStake.mul(1e18).div(stakeholderShares);
        uint currentRatio = getRatio();

        if (currentRatio <= stakedRatio) {
            return 0;
        }

        uint rewards = stakeholderShares.mul(currentRatio.sub(stakedRatio)).div(1e18);
        return rewards;
    }
}
