module LatentGaussianMixtureModel


using Distributions
using StatsBase, StatsFuns
using FastGaussQuadrature
using Yeppp

import GaussianMixtureTest: gmm, pn, decidepenalty
import StatsBase: RealArray, RealVector, RealMatrix, IntegerArray, IntegerVector, IntegerMatrix, IntUnitRange
import StatsFuns: logπ
export predictgamma, asymptoticdistribution, latentgmm, marginallikelihood, EMtest, FDR, coefpvalue, vcov

import StatsBase: coef, coeftable, confint, deviance, loglikelihood, nobs, stderr, vcov, residuals, predict, fit, model_response
export coef, coeftable, confint, deviance, loglikelihood, nobs, stderr, vcov, residuals, predict, fit, fit!, model_response
using DataFrames

include("model.jl")
export LGMModel, imputeY!
#include("MCEM.jl")

include("arithmetic.jl")
include("utility.jl")
include("EM.jl")
#include("FractionalImputation.jl")

PKGVERSION="v0.3.0"
export PKGVERSION
end # module
