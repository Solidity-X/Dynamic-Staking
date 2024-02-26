Hey guys,
Today another tutorial where I will show you how to setup a dynamic staking contract.

**what is dynamic staking?**
Dynamic Staking means that users can deposit and withdraw crypto A at any time without a time lock. Also rewards are not distributed by the means of a stable APY or token distribution. This means that tokens (rewards) can be deposited at any time and any amount.
```
using EnumerableSet for EnumerableSet.AddressSet;
using SafeMath for uint;

```

**What do we need to get started?**
For this tutorial I will use safemath and the EnumerableSet.AddressSet from Openzeppelin. 

**Variables**
We will first define two ERC20 variables that represent our deposit and our withdraw token. Also just because I like it, I will keep track of all depositor addresses and the total amount of the depositors with the addressSet.
```
IERC20 private depToken; // deposit token (LP)
IERC20 private rewToken; // reward token
EnumerableSet.AddressSet private stakeholders; // list of depositor addresses
```

We will also need to define a Struct for the deposits. We will call this Struct "Stake". We will need a variable **staked** which is the amount of deposited tokens and a variable **shares** which tells us how much of the staking pool and thus rewards a user owns.
```
struct Stake {
        uint staked;
        uint shares;
    }
```
Now we define some other basic variables as the owner and also other variables to keep track of some information such ass the total amount of deposited tokens and total amount of shares and if the contract is initialized.
```
    address public owner; // owner of the contract
    uint private totalStakes; // total amount of tokens deposited
    uint private totalShares; // total amount of shares issued
    bool private initialized; // if contract is initialized
```
In order to utilize our struct we need to create a mapping from a corresponding user address to our struct
```
mapping(address => Stake) private stakeholderToStake; // mapping from the depositor address to his information (tokens deposited etc.)
```
We will now define a onlyOwner modifier as we have a important function that should only be called by the owner.
```
    /*\
    function with this modifier can only be called by the owner
    \*/
    modifier onlyOwner() {
        require(msg.sender == owner, "caller not owner");
        _;
    }
```
To give easier access to UI's and track historical information later in development we will also add some events.
```
    event StakeAdded(address indexed stakeholder, uint amount, uint shares, uint timestamp); // this event emits on every deposit
    event StakeRemoved(address indexed stakeholder, uint amount, uint shares, uint reward, uint timestamp); // this event emits on every withdraw
```

**Functions**
**Initialize**
After the deployment of our contract we will first have to call the initialize function with a small amount of our deposit tokens. This is because otherwise we will encounter a **0 division**. We could counter this by checking that the values in the deposit function are non zero but this would in the long term cost a lot more gas for the users. Please note that the small amount of deposit tokens in the initilize functions are lost forever, thus are the rewards that these token accumulate. For this exact reason you should use a very small amount of tokens (<1) in order to initialize the contract.
The initialize function will also renounce ownership as there is no reason for ownership after deployment.
```
/*\
    initialize all values
    amount will be locked forever
    \*/
    function initialize(uint _amount) external onlyOwner {
        require(!initialized, "already initialized!");
        uint balBef = depToken.balanceOf(address(this));
        require(depToken.transferFrom(msg.sender, address(this), _amount), "transfer failed!");
        _amount = depToken.balanceOf(address(this)).sub(balBef);

        stakeholderToStake[address(0)] = Stake({
            staked: _amount,
            shares: _amount
        });
        totalStakes = _amount;
        totalShares = _amount;
        initialized = true;
        owner = address(0);
        emit StakeAdded(address(0), _amount, _amount, block.timestamp);
    }
```

**Deposit**
We make sure the contract is initialized and that the users deposits more than 0 tokens.
We add the amount of deposit and reward tokens in our contract and note it as **tbal**
The shares that the users receives is the **deposited amount * total shares / tbal**
```
    /*\
    stake tokens
    \*/
    function _deposit(address _account, uint _amount) private {
        require(initialized, "not initialized!");
        require(_amount > 0, "amount too small!");

        uint tbal = depToken.balanceOf(address(this)).add(rewToken.balanceOf(address(this)));
        uint shares = _amount.mul(totalShares).div(tbal);
        uint balBef = depToken.balanceOf(address(this));
        require(depToken.transferFrom(_account, address(this), _amount), "transfer failed!");
        _amount = depToken.balanceOf(address(this)).sub(balBef);

        stakeholders.add(_account);
        stakeholderToStake[_account] = Stake({
            staked: _amount,
            shares: shares
        });
        totalStakes = totalStakes.add(_amount);
        totalShares += shares;
        emit StakeAdded(_account, _amount, shares, block.timestamp);
    }
```

**Withdraw**
For the Withdraw we first call our **rewardOf()** function and then update all values, after that we will send him his reward and deposited tokens. The function will always withdraw 100% of tokens. As a dev you should however be able to easily change this.
```
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

```

**rewardOf**
We divide the deposited tokens of the user by the shares. This is the ratio at which the user deposited his tokens. Then we get the current ratio which is defined as **tbal / total shares**, where tbal stands for the combined amount of deposited and reward tokens. If the current ratio is smaller than the ratio at which a user has deposited then there are no rewards.
The reward is calculated as follows: the user shares * (current ratio - user ratio)
```
/*\
    get rewards that user received
    \*/
    function rewardOf(address stakeholder) public view returns (uint) {
        uint stakeholderStake = stakeOf(stakeholder);
        uint stakeholderShares = sharesOf(stakeholder);

        if (stakeholderShares == 0) {
            return 0;
        }

        uint stakedRatio = stakeholderStake.mul(1e18);
        uint currentRatio = stakeholderShares.mul(getRatio());
        
        if (currentRatio <= stakedRatio) {
            return 0;
        }
        
        uint rewards = currentRatio.sub(stakedRatio).div(1e18);
        return rewards;
    }
```

**Emergency withdraw** 
Now even tho there should be no errors or edge cases, there is always a non-zero chance of contract failure, this might also apply to reward tokens. For this exact reason there is a emergy withdraw feature that let's user withdraw all their deposit without receiving any rewards. The lost rewards are automaticlly distributed to the other users.
```
    /*\
    withdraw function if in emergency state (no rewards)
    \*/
   function emergencyWithdraw() external returns(bool) {
        uint stake = stakeholderToStake[msg.sender].staked;
        uint shares = stakeholderToStake[msg.sender].shares;

        delete stakeholderToStake[msg.sender];
        totalShares = totalShares.sub(shares);
        totalStakes = totalStakes.sub(stake);

        require(depToken.transfer(msg.sender, stake), "initial transfer failed!");

        stakeholders.remove(msg.sender);
        return true;
    }
```

**Misc**
There are some for less fundamental functions of this contract. There are more things do to such as maybe ass time locks and custom withdraw amounts. The whole code is up on [github](https://github.com/Solidity-X/Dynamic-Staking/tree/main)
And if you need a professional smart contract dev for your next project then contact me on telegram: @solidityX
