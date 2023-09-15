// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

enum TokenType {
    PUT,
    PUT_SPREAD,
    CALL,
    CALL_SPREAD
}

enum CouponType {
    NONE,
    FIXED,
    PHOENIX,
    PHOENIX_MEMORY,
    VANILLA
}

enum BarrierObservationFrequencyType {
    NONE,
    ONE_SECOND,
    ONE_DAY,
    ONE_WEEK,
    TWO_WEEKS,
    ONE_MONTH,
    TWO_MONTHS,
    THREE_MONTHS,
    SIX_MONTHS,
    NINE_MONTHS,
    ONE_YEAR
}

enum BarrierTriggerType {
    AUTOCALL,
    KNOCK_OUT,
    KNOCK_IN
}

enum BarrierExerciseType {
    DISCRETE,
    CONTINUOUS,
    EUROPEAN
}

/**
 * @dev common action types on margin engines
 */
enum ActionType {
    AddCollateral,
    RemoveCollateral,
    MintShort,
    BurnShort,
    MergeOptionToken, // These actions are defined in "DebitSpread"
    SplitOptionToken, // These actions are defined in "DebitSpread"
    AddLong,
    RemoveLong,
    SettleAccount,
    // actions that influence more than one subAccounts:
    // These actions are defined in "OptionTransferable"
    MintShortIntoAccount, // increase short (debt) position in one subAccount, increase long token directly to another subAccount
    TransferCollateral, // transfer collateral directly to another subAccount
    TransferLong, // transfer long directly to another subAccount
    TransferShort // transfer short directly to another subAccount
}
