module LatentGaussianMixtureModel


using Distributions
using StatsBase, StatsFuns
using FastGaussQuadrature
using Yeppp

import GaussianMixtureTest: gmm, pn, decidepenalty
import StatsBase: RealArray, RealVector, RealArray, IntegerArray, IntegerVector, IntegerMatrix, IntUnitRange
import StatsFuns: logπ
export predictgamma, asymptoticdistribution, latentgmm, marginallikelihood, EMtest, FDR
include("arithmetic.jl")
include("utility.jl")
#include("MCEM.jl")
include("EM.jl")
#include("FractionalImputation.jl")
# package code goes here

end # module
