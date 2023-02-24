// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "./ABDKMathQuad.sol";
import "../A3SQueue.sol";
import "../../interfaces/IA3SWalletFactoryV3.sol";
import "../A3SWalletFactoryV3.sol";
import "../../interfaces/IA3SQueue.sol";

library A3SQueueHelper {
    using ABDKMathQuad for uint256;
    using ABDKMathQuad for bytes16;

    /**
     * @dev Node structure
     *
     * - `prev` previous pointer, point to right.
     * - `next` previous pointer, point to left.
     * - `balance` calculated $A balance: only assigned value when node is pushed out of queue
     * - `inQueueTime` timestamp when pushed into queue.
     * - `outQueueTime` timestamp when pushed out of queue.
     * - `queueStatus` Node status.
     *
     */
    struct Node {
        address addr;
        address prev;
        address next;
        uint256 balance;
        uint64 inQueueTime;
        uint64 outQueueTime;
        queueStatus stat;
    }

    enum queueStatus {
        INQUEUE,
        PENDING,
        CLAIMED,
        STOLEN
    }

    function _mint(
        address _addr,
        address _token,
        address _vault,
        address _A3SWalletFactory,
        uint16 _lockingDay,
        mapping(address => Node) storage _addressNode
    ) internal {
        //Require minted addrss belongs to msg.sender
        require(
            IA3SWalletFactoryV3(_A3SWalletFactory).walletOwnerOf(_addr) ==
                msg.sender,
            "A3S: ONLY owner can mint"
        );
        require(
            _addressNode[_addr].outQueueTime > 0,
            "A3S: NOT valid to calim - not pushed"
        );
        require(
            _addressNode[_addr].stat == A3SQueueHelper.queueStatus.PENDING,
            "A3S: ONLY pending status could be claimed"
        );
        require(
            uint64(block.timestamp) - _addressNode[_addr].outQueueTime <
                _lockingDay * 1 days,
            "A3S: NOT valid to calim - out of queue exceed unlocking period"
        );
        uint256 _balance = _addressNode[_addr].balance;
        IERC20(_token).transferFrom(_vault, _addr, _balance);
        _addressNode[_addr].stat = queueStatus.CLAIMED;

        emit Mint(_addr, _balance);
    }

    function _steal(
        address _addr,
        address _token,
        address _tailIdx,
        address _vault,
        uint16 _lockingDay,
        mapping(address => Node) storage _addressNode
    ) internal {
        require(
            _addressNode[_addr].stat == A3SQueueHelper.queueStatus.PENDING,
            "A3S: ONLY pending status could be stolen"
        );
        require(
            uint64(block.timestamp) - _addressNode[_addr].outQueueTime >=
                _lockingDay * 1 days,
            "A3S: NOT valid to steal - not reaching locking period"
        );
        //ERC20 token transfer for _balance;
        uint256 _balance = _addressNode[_addr].balance;
        IERC20(_token).transferFrom(_vault, _tailIdx, _balance);
        _addressNode[_addr].balance = 0;
        _addressNode[_addr].stat = A3SQueueHelper.queueStatus.STOLEN;

        emit Steal(_tailIdx, _addr, _balance);
    }

    function _getTokenAmount(
        address _addr,
        address payable _A3SWalletFactory,
        mapping(address => Node) storage _address_node
    ) internal view returns (uint256 amount) {
        uint16[16] memory _fibonacci = [
            1,
            2,
            3,
            5,
            8,
            13,
            21,
            34,
            55,
            89,
            144,
            233,
            377,
            610,
            987,
            1597
        ];
        A3SWalletFactoryV3 a3sContract = A3SWalletFactoryV3(_A3SWalletFactory);
        uint256 r = 5;
        //Get DiffID
        uint256 _currID = uint256(
            IA3SWalletFactoryV3(_A3SWalletFactory).walletIdOf(_addr)
        );
        uint256 _diffID = a3sContract.tokenIdCounter() - _currID;
        //N = 1.1 + 0.1 * ()
        bytes16 _n = A3SQueueHelper._getN(_currID);
        //T: from _fibonacci array
        uint256 _T = 0;
        for (uint256 i = 0; i <= 15; i++) {
            if (
                ((block.timestamp - _address_node[_addr].inQueueTime) /
                    86400) >=
                _fibonacci[i] &&
                ((block.timestamp - _address_node[_addr].inQueueTime) / 86400) <
                _fibonacci[i + 1]
            ) {
                _T = _fibonacci[i];
            }
        }
        bytes16 _amount = ABDKMathQuad
            .log_2(_diffID.fromUInt())
            .div(ABDKMathQuad.log_2(_n))
            .mul(uint256(10**18).fromUInt())
            .mul(_T.fromUInt())
            .mul(r.fromUInt());
        amount = _amount.toUInt();
    }

    function _getN(uint256 _diffID) internal pure returns (bytes16 n) {
        bytes16 m = uint256(11).fromUInt().div(uint256(10).fromUInt());
        bytes16 q = uint256(1).fromUInt().div(uint256(10).fromUInt());
        bytes16 k = uint256(_diffID / uint256(100)).fromUInt();
        n = m.add(q.mul(k));
    }

    function _getExtendLength(uint64 _prevDayIncreCount)
        internal
        pure
        returns (uint64 extendLength)
    {
        uint8[21] memory _index = [
            0,
            18,
            32,
            42,
            50,
            58,
            62,
            67,
            71,
            73,
            77,
            78,
            81,
            82,
            84,
            85,
            86,
            87,
            88,
            89,
            90
        ];

        uint64 n = _prevDayIncreCount / 100;
        if (n >= 22) {
            extendLength = 90;
        } else {
            extendLength = uint64(_index[n - 1]);
        }
    }

    //Actual Calculate extended length with deviation
    //Right now is using _getExtendLength which hardcoded the values
    function _getExtendLength_new(uint64 _prevDayIncreCount)
        internal
        pure
        returns (uint64)
    {
        uint64 n = _prevDayIncreCount / 100;
        if (n == 1) return 0;
        //0.1
        bytes16 a = uint256(1).fromUInt().div(uint256(10).fromUInt());
        //Mn = 1 + 0.1 * n
        bytes16 Mn = uint256(1).fromUInt().add(
            a.mul(uint256(n - 1).fromUInt())
        );
        //Ln = Xn * (1 - 1/mm), Xn is preDayIncreCount
        //1 / Mn
        bytes16 x = uint256(1).fromUInt().div(Mn);
        //1 - 1/Mn
        bytes16 Ln = uint256(1).fromUInt().sub(x);
        bytes16 _extended = uint256(n)
            .fromUInt()
            .mul(uint256(100).fromUInt())
            .mul(Ln);
        return uint64(_extended.toUInt());
    }

    event Steal(address stealAddr, address stolenAddr, uint256 amount);
    event Mint(address addr, uint256 mintAmount);
}
