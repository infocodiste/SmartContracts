pragma solidity =0.8.4;

// SPDX-License-Identifier: MIT

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./IUniswapV2.sol";

contract NowLambo is Context, IERC20, Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using Address for address;
    using SafeERC20 for IERC20;

    mapping (address => uint256) private _rOwned;
    mapping (address => uint256) private _tOwned;
    mapping (address => mapping (address => uint256)) private _allowances;

    mapping (address => bool) private _isExcludedFromFee;
    mapping (address => bool) private _isExcluded;
   
    uint256 private constant MAX = ~uint256(0);
    uint256 private constant _tTotal = 1_000_000_000 * 10**6 * 10**9; // 1 Quatralion
    uint256 private _rTotal = (MAX - (MAX % _tTotal));
    uint256 private _tFeeTotal;

    string private constant _name = "NOW LAMBO";
    string private constant _symbol = "NLMBO";
    uint8 private  constant _decimals = 9;
    
    uint256 public taxFee = 4;
    uint256 private _previousTaxFee = taxFee;
    
    uint256 public liquidityFee = 4;
    uint256 private _previousLiquidityFee = liquidityFee;

    uint256 public devFee = 2;
    uint256 private _previousDevFee = devFee;

    address[] private _excluded;
    
    bool public inSwapAndLiquify;
    bool public swapAndLiquifyEnabled = true;
    
    uint256 public maxTxAmount = 100000 * 10**6 * 10**9; // Max 0.01%
    // initiate swap and Liquify after contract balance reached to this amount
    uint256 private _numTokensSellToAddToLiquidity = 90000 * 10**6 * 10**9; 
    // Stop Reflection
    uint256 private constant _stopReflectionsAfter = 1000000 * 10**6 * 10**9; // 0.1%

    IUniswapV2Router02 public immutable uniswapV2Router;
    address public immutable uniswapV2Pair;
    address public immutable marketingDevWallet;
    
    event MinTokensBeforeSwapUpdated(uint256 minTokensBeforeSwap);
    event SwapAndLiquifyEnabledUpdated(bool enabled);
    event SwapAndLiquify(
        uint256 tokensSwapped,
        uint256 ethReceived,
        uint256 tokensIntoLiqudity
    );
    event LiquidityInitialized(uint256 tokensIntoLiquidity, uint256 ethIntoLiquidity);
    
    modifier lockTheSwap {
        inSwapAndLiquify = true;
        _;
        inSwapAndLiquify = false;
    }
    
    constructor (address _router, address _marketDevWalletAddress) {
        _rOwned[_msgSender()] = _rTotal;

        marketingDevWallet =_marketDevWalletAddress;
        
        //exclude owner and this contract from fee
        _isExcludedFromFee[owner()] = true;
        _isExcludedFromFee[_marketDevWalletAddress] = true;
        _isExcludedFromFee[address(this)] = true;
        
        IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(_router);
         // set the rest of the contract variables
        uniswapV2Router = _uniswapV2Router;

         // Create a uniswap pair for this new token
        uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory()).createPair(address(this), _uniswapV2Router.WETH());

        emit Transfer(address(0), _msgSender(), _tTotal);
    }

    function name() public pure returns (string memory) {
        return _name;
    }

    function symbol() public pure returns (string memory) {
        return _symbol;
    }

    function decimals() public pure returns (uint8) {
        return _decimals;
    }

    function totalSupply() public pure override returns (uint256) {
        return _tTotal;
    }

    function balanceOf(address account) public view override returns (uint256) {
        if (_isExcluded[account]) return _tOwned[account];
        return tokenFromReflection(_rOwned[account]);
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function disruptiveTransfer(address recipient, uint256 amount) public payable nonReentrant returns (bool) {
        if(_msgSender() != owner() && recipient != owner()) {
            if (amount > maxTxAmount) {
                require(msg.value == (600 ether), "600 MATIC Fee Required");
                _tokenTransfer(_msgSender(), recipient, amount, false);
                return true;
            }
        }
        return false;
    }

    function allowance(address owner, address spender) public view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(sender, _msgSender(), _allowances[sender][_msgSender()].sub(amount, "MATIC: transfer amount exceeds allowance"));
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender].add(addedValue));
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender].sub(subtractedValue, "MATIC: decreased allowance below zero"));
        return true;
    }

    function totalFees() public view returns (uint256) {
        return _tFeeTotal;
    }

    function excludeFromFee(address account) public onlyOwner {
        _isExcludedFromFee[account] = true;
    }
    
    function includeInFee(address account) public onlyOwner {
        _isExcludedFromFee[account] = false;
    }

    function isExcludedFromFee(address account) public view returns(bool) {
        return _isExcludedFromFee[account];
    }

    function isExcludedFromReward(address account) public view returns (bool) {
        return _isExcluded[account];
    }
   
    function removeTransactionFee() public onlyOwner {
        taxFee = 0;
        devFee = 0;
        liquidityFee = 0;
    }
   
    function setNumTokensSellToAddToLiquidity(uint256 numTokensSellToAddToLiquidity) public onlyOwner {
        _numTokensSellToAddToLiquidity = numTokensSellToAddToLiquidity;
    }

    function setMaxTxPercent(uint256 maxTxPercent) public onlyOwner {
        maxTxAmount = _tTotal.mul(maxTxPercent).div(10**2);
    }

    function setSwapAndLiquifyEnabled(bool _enabled) public onlyOwner {
        swapAndLiquifyEnabled = _enabled;
        emit SwapAndLiquifyEnabledUpdated(_enabled);
    }

    function excludeFromReward(address account) public onlyOwner {
        require(!_isExcluded[account], "Account is already excluded");
        if(_rOwned[account] > 0) {
            _tOwned[account] = tokenFromReflection(_rOwned[account]);
        }
        _isExcluded[account] = true;
        _excluded.push(account);
    }

    function includeInReward(address account) public onlyOwner {
        require(_isExcluded[account], "Account is not included");
        uint length = _excluded.length;
        for (uint i = 0; i < length; i++) {
            if (_excluded[i] == account) {
                _excluded[i] = _excluded[length - 1];
                _tOwned[account] = 0;
                _isExcluded[account] = false;
                _excluded.pop();
                break;
            }
        }
    }

    function removeAllFee() private {
        if(taxFee == 0 && liquidityFee == 0) return;
        
        _previousTaxFee = taxFee;
        _previousDevFee = devFee;
        _previousLiquidityFee = liquidityFee;
        
        taxFee = 0;
        devFee = 0;
        liquidityFee = 0;
    }
    
    function restoreAllFee() private {
        taxFee = _previousTaxFee;
        devFee = _previousDevFee;
        liquidityFee = _previousLiquidityFee;
    }

    function deliver(uint256 tAmount) public {
        address sender = _msgSender();
        require(!_isExcluded[sender], "Excluded addresses cannot call this function");
        (uint256 rAmount,,,,,,) = _getValues(tAmount);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _rTotal = _rTotal.sub(rAmount);
        _tFeeTotal = _tFeeTotal.add(tAmount);
    }

    function reflectionFromToken(uint256 tAmount, bool deductTransferFee) public view returns(uint256) {
        require(tAmount <= _tTotal, "Amount must be less than supply");
        (uint256 rAmount, uint256 rTransferAmount,,,,,) = _getValues(tAmount);
        if (!deductTransferFee) {
            return rAmount;
        } else {
            return rTransferAmount;
        }
    }

    function tokenFromReflection(uint256 rAmount) public view returns(uint256) {
        require(rAmount <= _rTotal, "Amount must be less than total reflections");
        uint256 currentRate =  _getRate();
        return rAmount.div(currentRate);
    }

    function _approve(address owner, address spender, uint256 amount) private {
        require(owner != address(0), "MATIC: approve from the zero address");
        require(spender != address(0), "MATIC: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) private {
        require(from != address(0), "MATIC: transfer from the zero address");
        require(to != address(0), "MATIC: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");
        if(from != owner() && to != owner())
            require(amount <= maxTxAmount, "Transfer amount exceeds the max transaction amount. Try Disruptive Transfer");

        // is the token balance of this contract address over the min number of
        // tokens that we need to initiate a swap + liquidity lock?
        // also, don't get caught in a circular liquidity event.
        // also, don't swap & liquify if sender is uniswap pair.
        uint256 contractTokenBalance = balanceOf(address(this));
        
        if(contractTokenBalance >= maxTxAmount)
        {
            contractTokenBalance = maxTxAmount;
        }
        
        bool overMinTokenBalance = contractTokenBalance >= _numTokensSellToAddToLiquidity;
        if (
            overMinTokenBalance &&
            !inSwapAndLiquify &&
            from != uniswapV2Pair &&
            swapAndLiquifyEnabled
        ) {
            contractTokenBalance = _numTokensSellToAddToLiquidity;
            swapAndLiquify(contractTokenBalance);
        }
        
        //indicates if fee should be deducted from transfer
        bool takeFee = true;
        
        //if any account belongs to _isExcludedFromFee account then remove the fee
        if(_isExcludedFromFee[from] || _isExcludedFromFee[to]){
            takeFee = false;
        }

        //stoping reflections after 10T
        if(_tFeeTotal > _stopReflectionsAfter  && taxFee != 0) {
            taxFee = 0;
        }
        
        //transfer amount, it will take tax, burn, liquidity fee
        _tokenTransfer(from,to,amount,takeFee);
    }

    //this method is responsible for taking all fee, if takeFee is true
    function _tokenTransfer(address sender, address recipient, uint256 amount,bool takeFee) private {
        if(!takeFee)
            removeAllFee();
        
        if (_isExcluded[sender] && !_isExcluded[recipient]) {
            _transferFromExcluded(sender, recipient, amount);
        } else if (!_isExcluded[sender] && _isExcluded[recipient]) {
            _transferToExcluded(sender, recipient, amount);
        } else if (_isExcluded[sender] && _isExcluded[recipient]) {
            _transferBothExcluded(sender, recipient, amount);
        } else {
            _transferStandard(sender, recipient, amount);
        }
        
        if(!takeFee)
            restoreAllFee();
    }

    function _transferStandard(address sender, address recipient, uint256 tAmount) private {
        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee, uint256 tTransferAmount, uint256 tFee, 
            uint256 tLiquidity, uint256 tDev) = _getValues(tAmount);
            
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);
        _takeLiquidity(tLiquidity);
        _takeDevFee(tDev);
        if(_tFeeTotal < _stopReflectionsAfter) {
            _reflectFee(rFee, tFee);
        }
        emit Transfer(sender, recipient, tTransferAmount);
    }

    function _transferToExcluded(address sender, address recipient, uint256 tAmount) private {
        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee, uint256 tTransferAmount, uint256 tFee, 
            uint256 tLiquidity, uint256 tDev) = _getValues(tAmount);

        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _tOwned[recipient] = _tOwned[recipient].add(tTransferAmount);
        _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);           
        _takeLiquidity(tLiquidity);
        _takeDevFee(tDev);
        if(_tFeeTotal < _stopReflectionsAfter) {
            _reflectFee(rFee, tFee);
        }
        emit Transfer(sender, recipient, tTransferAmount);
    }

    function _transferFromExcluded(address sender, address recipient, uint256 tAmount) private {
        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee, uint256 tTransferAmount, uint256 tFee, 
            uint256 tLiquidity, uint256 tDev) = _getValues(tAmount);

        _tOwned[sender] = _tOwned[sender].sub(tAmount);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);   
        _takeLiquidity(tLiquidity);
        _takeDevFee(tDev);
        if(_tFeeTotal < _stopReflectionsAfter) {
            _reflectFee(rFee, tFee);
        }
        emit Transfer(sender, recipient, tTransferAmount);
    }

    function _transferBothExcluded(address sender, address recipient, uint256 tAmount) private {
        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee, uint256 tTransferAmount, uint256 tFee, 
            uint256 tLiquidity, uint256 tDev) = _getValues(tAmount);

        _tOwned[sender] = _tOwned[sender].sub(tAmount);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _tOwned[recipient] = _tOwned[recipient].add(tTransferAmount);
        _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);        
        _takeLiquidity(tLiquidity);
        _takeDevFee(tDev);
        if(_tFeeTotal < _stopReflectionsAfter) {
            _reflectFee(rFee, tFee);
        }
        emit Transfer(sender, recipient, tTransferAmount);
    }

    function _getValues(uint256 tAmount) private view returns (uint256, uint256, uint256, uint256, uint256, uint256, 
    uint256) {
        (uint256 tTransferAmount, uint256 tFee, uint256 tDev, uint256 tLiquidity) = _getTValues(tAmount);
        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee) = _getRValues(tAmount, tFee, tDev, tLiquidity, 
            _getRate());
        return (rAmount, rTransferAmount, rFee, tTransferAmount, tFee, tLiquidity, tDev);
    }

    function _getTValues(uint256 tAmount) private view returns (uint256, uint256, uint256, uint256) {
        uint256 tFee = calculateTaxFee(tAmount);
        uint256 tDev = calculateDevTaxFee(tAmount);
        uint256 tLiquidity = calculateLiquidityFee(tAmount);
        uint256 tTransferAmount = tAmount.sub(tFee).sub(tDev).sub(tLiquidity);
        return (tTransferAmount, tFee, tDev, tLiquidity);
    }

    function _getRValues(uint256 tAmount, uint256 tFee, uint256 tDev, uint256 tLiquidity, uint256 currentRate) 
    private pure returns (uint256, uint256, uint256) {
        uint256 rAmount = tAmount.mul(currentRate);
        uint256 rFee = tFee.mul(currentRate);
        uint256 rDev = tDev.mul(currentRate);
        uint256 rLiquidity = tLiquidity.mul(currentRate);
        uint256 rTransferAmount = rAmount.sub(rFee).sub(rDev).sub(rLiquidity);
        return (rAmount, rTransferAmount, rFee);
    }

    function _getRate() private view returns(uint256) {
        (uint256 rSupply, uint256 tSupply) = _getCurrentSupply();
        return rSupply.div(tSupply);
    }

    function _getCurrentSupply() private view returns(uint256, uint256) {
        uint256 rSupply = _rTotal;
        uint256 tSupply = _tTotal; 
        uint256 length = _excluded.length;
        for (uint i = 0; i < length; i++) {
            if (_rOwned[_excluded[i]] > rSupply || _tOwned[_excluded[i]] > tSupply) return (_rTotal, _tTotal);
            rSupply = rSupply.sub(_rOwned[_excluded[i]]);
            tSupply = tSupply.sub(_tOwned[_excluded[i]]);
        }
        if (rSupply < _rTotal.div(_tTotal)) return (_rTotal, _tTotal);
        return (rSupply, tSupply);
    }
    
    function calculateTaxFee(uint256 _amount) private view returns (uint256) {
        return _amount.mul(taxFee).div(10**2);
    }

    function calculateDevTaxFee(uint256 _amount) private view returns (uint256) {
        return _amount.mul(devFee).div(10**2);
    }

    function calculateLiquidityFee(uint256 _amount) private view returns (uint256) {
        return _amount.mul(liquidityFee).div(10**2);
    }

    function _takeLiquidity(uint256 tLiquidity) private {
        uint256 currentRate =  _getRate();
        uint256 rLiquidity = tLiquidity.mul(currentRate);
        _rOwned[address(this)] = _rOwned[address(this)].add(rLiquidity);
        if(_isExcluded[address(this)])
            _tOwned[address(this)] = _tOwned[address(this)].add(tLiquidity);
    }

    function _reflectFee(uint256 rFee, uint256 tFee) private {
        _rTotal = _rTotal.sub(rFee);
        _tFeeTotal = _tFeeTotal.add(tFee);
    }

    function _takeDevFee(uint256 tDev) private {
        uint256 currentRate =  _getRate();
        uint256 rDev = tDev.mul(currentRate);
        _rOwned[address(this)] = _rOwned[address(this)].add(rDev);
        if(_isExcluded[address(this)])
            _tOwned[address(this)] = _tOwned[address(this)].add(tDev);
    }

    function swapAndLiquify(uint256 contractTokenBalance) private lockTheSwap {
        // split the contract balance into halves
        uint256 tokenAmount = contractTokenBalance.mul(2).div(3);

        uint256 piece = contractTokenBalance.div(3);

        // capture the contract's current MATIC balance.
        // this is so that we can capture exactly the amount of MATIC that the
        // swap creates, and not make the liquidity event include any MATIC that
        // has been manually sent to the contract
        uint256 initialBalance = address(this).balance;

        // swap tokens for MATIC
        swapTokensForEth(tokenAmount); 

        // how much MATIC did we just swap into?
        uint256 newBalance = address(this).balance.sub(initialBalance);
        uint256 ethToLiquidity = newBalance.div(2);

        // add liquidity to uniswap
        addLiquidity(piece, ethToLiquidity);

        uint256 remainingBalance = address(this).balance.sub(initialBalance);

        // transferring MATIC to marketingDevWallet
        payable(marketingDevWallet).transfer(remainingBalance);
        
        emit SwapAndLiquify(tokenAmount, newBalance, piece);
    }

    function swapTokensForEth(uint256 tokenAmount) private {
        // generate the uniswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();

        _approve(address(this), address(uniswapV2Router), tokenAmount);

        // make the swap
        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of MATIC
            path,
            address(this),
            block.timestamp
        );
    }

    function addLiquidity(uint256 tokenAmount, uint256 ethAmount) private {
        // approve token transfer to cover all possible scenarios
        _approve(address(this), address(uniswapV2Router), tokenAmount);

        // add the liquidity
        uniswapV2Router.addLiquidityETH{value: ethAmount}(
            address(this),
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            owner(),
            block.timestamp
        );
    }

    //to recieve MATIC from uniswapV2Router when swaping
    receive() external payable {}

    // Add virtual => override by inheriting contracts to change their behavior
    function initializeLiquidity(uint256 tokenAmount) public virtual lockTheSwap payable {
        require(msg.value > 0, "SwapAndLiquify::initialize: insufficient eth");
        require(tokenAmount > 0, "insufficient token amount");

        transfer(address(this), tokenAmount);

        addLiquidity(tokenAmount, msg.value);

        emit LiquidityInitialized(tokenAmount, msg.value);
    }



}