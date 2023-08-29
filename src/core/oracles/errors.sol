// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

error OC_CannotReportForFuture();

error OC_PriceNotReported();

error OC_PriceReported();

error OC_ZeroAddress();

///@dev cannot dispute the settlement price after dispute period is over
error OC_DisputePeriodOver();

///@dev cannot force-set an settlement price until grace period is passed and no one has set the price.
error OC_GracePeriodNotOver();

///@dev owner trying to set a dispute period that is invalid
error OC_InvalidPeriod();

///@dev used when arrays for assigning mappings differ in size
error OC_ArgumentsLengthError();

// Chainlink oracle

error CL_AggregatorNotSet();

error CL_StaleAnswer();

error CL_RoundIdTooSmall();

error CL_PriceNotReported();

// Pyth oracle

error PY_InvalidPriceFeedID();

error PY_DifferentPublishProvidedTimestamps();

error PY_AssetPriceFeedNotSet();

error PY_PythPriceConversionError();

// Instrument oracle

error IO_InvalidTimestamp();
