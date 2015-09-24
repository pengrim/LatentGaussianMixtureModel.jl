#The utility functions
#Lanfeng Pan
#Oct 29, 2014

function pn(sigma1::Float64,  sigmahat::Float64; an::Float64 = .25)
    -(sigmahat / sigma1 + log(sigma1 / sigmahat) ) * an
end
pn(sigma1::Vector{Float64},  sigmahat::Float64; an::Float64 = .25)=Float64[pn(sigma1[i], sigmahat, an=an) for i in 1:length(sigma1)]
pn(sigma1::Vector{Float64},  sigmahat::Vector{Float64}; an::Float64 = .25)=Float64[pn(sigma1[i], sigmahat[i], an=an) for i in 1:length(sigma1)]



#copy from NumericExtensions, to avoid the annoyed warnings
function eachrepeat{T}(x::AbstractVector{T}, rt::Integer)
    # repeat each element in x for rt times

    nx = length(x)
    r = Array(T, nx * rt)
    j = 0
    for i = 1 : nx
        @inbounds xi = x[i]
        for i2 = 1 : rt
            @inbounds r[j += 1] = xi
        end
    end
    return r
end

function eachrepeat{T,I<:Integer}(x::AbstractVector{T}, rt::AbstractArray{I})
    nx = length(x)
    nx == length(rt) || throw(ArgumentError("Inconsistent array lengths."))

    r = Array(T, sum(rt))
    j = 0
    for i = 1 : nx
        @inbounds xi = x[i]
        for i2 = 1 : rt[i]
            @inbounds r[j += 1] = xi
        end
    end
    return r
end


function tapply{T,I<:Integer}(x::AbstractVecOrMat{T}, index::AbstractVecOrMat{I}, f::Function, indexlabels::AbstractVector{I})

    res = zeros(length(indexlabels))
    for i in 1:length(indexlabels)
        res[i] = f(x[findin(index, indexlabels[i])])
    end
    res
end

function stopRule(pa::Vector, pa_old::Vector; tol=.005)
    maximum(abs(pa .- pa_old)./(abs(pa).+.001)) < tol
end


#accept prob for γᵢ = ΠΠ(e(ηᵒy)+1)/(e(ηy)+1) #* exp(((γold - mu)²-(γnew-mu)²)/2σ²)exp((γᵒ-γⁿ)²/2gsd²)
function q_gamma(sample_gamma_new::Array{Float64,1}, sample_gamma::Array{Float64,1}, xb::Array{Float64,1}, Y::AbstractArray{Bool, 1}, facility::Vector{Int64}, mu::Vector{Float64}, sigmas::Vector{Float64}, L::Vector{Int64}, L_new::Vector{Int64}, llvec::Vector{Float64}, llvecnew::Vector{Float64},ll_nF::Vector{Float64}, nF::Int, N::Int)

    # llvec[:] = xb .+ sample_gamma[facility]
    relocate!(llvec, sample_gamma, facility, N)
    Yeppp.add!(llvec, llvec, xb)
    # llvecnew[:] = xb .+ sample_gamma_new[facility]
    relocate!(llvecnew, sample_gamma_new, facility, N)
    Yeppp.add!(llvecnew, llvecnew, xb)

    # map!(RcpLogistic(), llvec, llvec, Y)
    # map!(RcpLogistic(), llvecnew, llvecnew, Y)
    rcplogistic!(llvec, Y)
    rcplogistic!(llvecnew, Y)

    divide!(llvec, llvecnew, N)

    # for i in 1:nF
    #     ll_nF[i] = prod(llvec[coll_nF[i]]) * pdf(Normal(mu[L_new[i]], sigmas[L_new[i]]), sample_gamma_new[i])/ pdf(Normal(mu[L[i]], sigmas[L[i]]), sample_gamma[i])
    # end
    for i in 1:nF
        @inbounds ll_nF[i] = pdf(Normal(mu[L_new[i]], sigmas[L_new[i]]), sample_gamma_new[i])/ pdf(Normal(mu[L[i]], sigmas[L[i]]), sample_gamma[i])
    end

    for i in 1:N
        @inbounds ll_nF[facility[i]] *= llvec[i]
    end

    nothing

end

#Estimate gaussian mixture parameters given the initial value of γ
function gmm(x::Vector{Float64}, ncomponent::Int, wi_init::Vector{Float64}, mu_init::Vector{Float64}, sigmas_init::Vector{Float64}; whichtosplit::Int64=1, tau::Float64=.5, mu_lb::Vector{Float64}=-Inf.*ones(wi_init), mu_ub::Vector{Float64}=Inf.*ones(wi_init), an::Float64=0.25, sn::Vector{Float64}=ones(wi_init).*var(x), maxiter::Int64=10000, tol=.001, wifixed=false)

    nF = length(x)
    #ncomponent = length(wi_init)
    tau = min(tau, 1-tau)
    # sn = var(x)
    wi = copy(wi_init)
    mu = copy(mu_init)
    sigmas = copy(sigmas_init)
    
    if wifixed
        wi_tmp = wi[whichtosplit]+wi[whichtosplit+1]
        wi[whichtosplit] = wi_tmp*tau
        wi[whichtosplit+1] = wi_tmp*(1-tau)
        mu = min(max(mu, mu_lb), mu_ub)
    end
    
    pwi = ones(nF, ncomponent) ./ ncomponent
    for iter_em in 1:maxiter
        for i in 1:nF
            pwi[i, :] = ratiosumexp(-(mu .- x[i]).^2 ./ (2 .* sigmas .^ 2), wi ./ sigmas)
        end

        wi_old=copy(wi)
        mu_old=copy(mu)
        sigmas_old=copy(sigmas)

        for j in 1:ncomponent
            colsum = sum(pwi[:, j])
            wi[j] = colsum / nF
            mu[j] = wsum(pwi[:,j] ./ colsum, x)
            sigmas[j] = sqrt((wsum(pwi[:,j], (x .- mu[j]).^2) + 2 * an * sn[j]) / (sum(pwi[:,j]) + 2*an))

        end
        # sigmasmax = maximum(sigmas)
        # for j in 1:ncomponent
        #     if sigmas[j] / sigmasmax < .01
        #         sigmas[j] = .01 * sigmasmax
        #     end
        # end

        if wifixed
            wi_tmp = wi[whichtosplit]+wi[whichtosplit+1]
            wi[whichtosplit] = wi_tmp*tau
            wi[whichtosplit+1] = wi_tmp*(1-tau)
            mu = min(max(mu, mu_lb), mu_ub)
        end
        #println(wi, mu, sigmas, "----")

        if stopRule(vcat(wi, mu, sigmas), vcat(wi_old, mu_old, sigmas_old), tol=tol)
            break
        end
    end
    m = MixtureModel(map((u, v) -> Normal(u, v), mu, sigmas), wi)

    ml = sum(logpdf(m, x)) + sum(pn(sigmas.^2, sn)) #+ log(1 - abs(1 - 2*tau))
    return (wi, mu, sigmas, ml)
end


#for maxposterior
function mpe_goalfun(input::Vector{Float64}, storage::Vector, X::Matrix{Float64}, Y::AbstractArray{Bool, 1}, facility::Vector{Int64}, nF::Int, llvec::Vector{Float64},llvecnew::Vector{Float64})

    N,J=size(X)
    mygamma= input[1:nF]
    mybeta = input[(nF+1):(nF+J)]
    mytheta = input[nF+J+1]
    llvec[:] = X*mybeta

    Yeppp.add!(llvec, mygamma[facility], llvec)
    # map!(Exp_xy(), llvec, llvec, Y)
    negateiftrue!(llvec, Y)
    exp!(llvec, llvec)

    if length(storage)>0
        fill!(storage, 0.0)
        llvecnew[:] = llvec
        # map!(Xy1x(), llvecnew, llvecnew, Y)
        x1x!(llvecnew)
        negateiffalse!(llvecnew, Y)

        for i in 1:nF
            storage[i] =  - mygamma[i]/mytheta
        end
        for i in 1:N
            storage[facility[i]] += llvecnew[i]
        end
        for irow in 1:N
            for j in 1:J
                storage[j+nF] += llvecnew[irow] * X[irow,j]
            end
        end
        storage[nF+J+1] = sumabs2(mygamma) / (mytheta * mytheta) /2 - nF/mytheta/2

        for i in 1:length(input)
            storage[i] = storage[i] / N
        end
    end
    # map!(Log1p(), llvec, llvec)
    log1p!(llvec)

    -mean(llvec) - sumabs2(mygamma)/N/mytheta/2 - log(mytheta) * nF / 2/N
end
function maxposterior(X::Matrix{Float64}, Y::AbstractArray{Bool, 1}, facility::Vector{Int64})

    N,J = size(X)
    nF = length(unique(facility))

    bag = [rand(Normal(), nF), ones(J+1);]
    p=1+J+nF
    opt_init = Opt(:LD_LBFGS, p)
    lower_bounds!(opt_init, [-Inf .* ones(nF+J), 0.0;])
    llvec = zeros(N)
    llvecnew = zeros(N)
    max_objective!(opt_init, (input, storage)->mpe_goalfun(input, storage, X, Y, facility, nF, llvec, llvecnew))
    (minf,bag,ret) = optimize(opt_init, bag)
    (bag[1:nF], bag[(1+nF):((nF+J))], bag[nF+J+1])
end


function marginallikelihood(beta_new::Array{Float64,1}, X::Matrix{Float64}, Y::AbstractArray{Bool, 1}, facility::Vector{Int64}, nF::Int64, wi::Vector{Float64}, mu::Vector{Float64}, sigmas::Vector{Float64}, ghx::Vector{Float64}, ghw::Vector{Float64})

    N,J = size(X)
    M = length(ghx)
    C = length(wi)
    xb = X*beta_new
    ll_nF=zeros(nF)
    # sumlog_nF = zeros(nF)
    llvec = zeros(N)
    sumlogmat = zeros(nF, M*C)
    for jcom in 1:C
        for ix in 1:M
            fill!(llvec, ghx[ix]*sigmas[jcom]*sqrt(2)+mu[jcom])
            add!(llvec, llvec, xb)
            negateiftrue!(llvec, Y)
            exp!(llvec, llvec)
            log1p!(llvec)
            ixM = ix+M*(jcom-1)
            for i in 1:N
                @inbounds sumlogmat[facility[i], ixM] -= llvec[i]
            end
            for i in 1:nF
                sumlogmat[i, ixM] += log(wi[jcom]) + log(ghw[ix])
            end
        end

    end
    for i in 1:nF
        ll_nF[i] = logsumexp(sumlogmat[i,:])
    end

    sum(ll_nF) - nF*log(pi)/2
end

#The first part of Q function for beta, divided by -N
#the goal and gradient function for estimation β
#goal = 1/N ∑∑∑mean [log(1+exp(-η_{im}yᵢ)) for m in 1:M ]
#gradient = 1/N ∑∑∑mean [yᵢx[i,:]/(1+exp(η_{im}yᵢ)) for m in 1:M ]
function Q1(beta_new::Array{Float64,1}, storage::Vector, X::Matrix{Float64}, Y::AbstractArray{Bool, 1}, sample_gamma_mat::Matrix{Float64},facility::Vector{Int64}, llvec::Vector{Float64}, llvecnew::Vector{Float64})

    N,J = size(X)
    xb = X*beta_new
    ll=0.0
    if length(storage)>0
        fill!(storage, 0.0)
    end
    M = size(sample_gamma_mat,2)
    for jcol in 1:M
        #llvec[:] = xb
        relocate!(llvec, sample_gamma_mat[:,jcol], facility, N)
        Yeppp.add!(llvec, llvec, xb)
        #add!(llvec, sample_gamma_mat[facility, jcol], llvec)

        # map!(Exp_xy(), llvec, llvec, Y)
        negateiftrue!(llvec, Y)
        exp!(llvec, llvec)
        if length(storage) > 0
            llvecnew[:] = llvec
            # map!(Xy1x(), llvecnew, llvecnew, Y)
            x1x!(llvecnew)
            negateiffalse!(llvecnew, Y)

            for irow in 1:N
                for j in 1:J
                    @inbounds storage[j] += llvecnew[irow] * X[irow,j]
                end
            end
        end
        # map!(Log1p(), llvec, llvec)
        log1p!(llvec)
        ll += sum(llvec)
    end

    if length(storage)>0
        for j in 1:J
            storage[j] = storage[j] / M
        end
    end
    -ll/M
end

macro GibbsLgamma()
    quote
        #Gibbs samping for M+M_discard times
        for iter_gibbs in 1:(M+M_discard)
            xb  = X*β

            #update Lᵢ
            #tmp_p[:]=tmp_p0
            wi_divide_sigmas = zeros(wi)
            inv_2sigmas_sq = ones(sigmas) .* 1e20
            for i in 1:length(wi)
                if sigmas[i] == 0.0
                    wi_divide_sigmas[i] = 0.0
                    inv_2sigmas_sq[i] = 1e20
                elseif isnan(sigmas[i])
                    warn("sigmas = $sigmas")
                    return(wi, mu, sigmas, β, -Inf)
                else
                    wi_divide_sigmas[i] = wi[i]/sigmas[i]
                    inv_2sigmas_sq[i] = 0.5 / sigmas[i]^2
                end
            end
            for i in 1:nF
                tmp_p[:] = ratiosumexp(-(mu .- sample_gamma[i]).^2 .* inv_2sigmas_sq, wi_divide_sigmas)
                L_new[i] = rand(Categorical(tmp_p))
                sample_gamma_new[i] = rand(Normal(sample_gamma[i], proposingsigma))
            end

            #update γᵢ;
            #Calculate the accept probability, stored in ll_nF
            q_gamma(sample_gamma_new, sample_gamma, xb, Y,facility, mu, sigmas, L, L_new, llvec, llvecnew, ll_nF, nF, N)
            for i in 1:nF
                if rand() < ll_nF[i]
                    sample_gamma[i] = sample_gamma_new[i]
                end
                L[i] = L_new[i]
            end

            #only keep samples after M_discard
            jcol = iter_gibbs - M_discard
            if jcol > 0
                sample_gamma_mat[:, jcol] = sample_gamma
                wipool[:] = wipool .+ counts(L, 1:ncomponent)
                mupool[:] = mupool .+ tapply(sample_gamma, L, sum, [1:ncomponent;])
                sigmaspool[:] = sigmaspool .+ tapply(sample_gamma.^2, L, sum, [1:ncomponent;])
            end
        end
    end
end

#The main function
#X, Y, facility
#nF is the number of facilities
#intial values of β, ω, μ and σ must be supplied

function latentgmm(X::Matrix{Float64}, Y::AbstractArray{Bool, 1}, facility::Vector{Int64}, ncomponent::Int, β_init::Vector{Float64}, wi_init::Vector{Float64}, mu_init::Vector{Float64}, sigmas_init::Vector{Float64}; Mmax::Int=10000, M_discard::Int=1000, maxiteration::Int=100, initial_iteration::Int=0, tol::Real=.005, proposingsigma::Float64=1.0, ngh::Int=1000, sn::Vector{Float64}=maximum(sigmas_init.^2).*ones(ncomponent), an::Float64=0.25)

    # initialize theta
    N,J=size(X)
    nF = maximum(facility)
    M = Mmax
    wi = copy(wi_init)
    mu = copy(mu_init)
    sigmas = copy(sigmas_init)

    β = copy(β_init)
    beta_old = randn(J)
    ghx, ghw = gausshermite(ngh)
    #Preallocate the storage space, reusable for each iteration
    # L_mat = zeros(Int64, (nF, M))
    L = rand(Categorical(wi), nF)
    L_new = rand(Categorical(wi), nF)
    sample_gamma = zeros(nF)
    sample_gamma_new = zeros(nF)
    sample_gamma_mat = zeros(nF, M)
    llvec = zeros(N)
    llvecnew = zeros(N)
    ll_nF = zeros(nF)
    wipool = zeros(ncomponent)
    mupool = zeros(ncomponent)
    sigmaspool = zeros(ncomponent)
    tmp_p=ones(ncomponent) / ncomponent

    ################################################################################################################
    #iterattion begins here

    no_iter=1
    M = 2000
    Q_maxiter = 2
    for iter_em in 1:maxiteration
        if iter_em == (initial_iteration + 1)
            M = Mmax
            Q_maxiter = 10
        end

        for i in 1:nF
            L[i] = rand(Categorical(wi))
            sample_gamma[i] = mean(sample_gamma_mat[i, :]) # rand(Normal(mu[L[i]], sigmas[L[i]]))  
        end
        fill!(wipool, 0.0)
        fill!(mupool, 0.0)
        fill!(sigmaspool, 0.0)

        #Gibbs samping for M+M_discard times
        @GibbsLgamma
        for j in 1:ncomponent
            if wipool[j] == 0
                wipool[j] = 1
            end
        end
        wi_old=copy(wi)
        mu_old=copy(mu)
        sigmas_old = copy(sigmas)
        #update wi, mu and sigmas
        
        wi = wipool ./ sum(wipool)
        mu = mupool ./ wipool
        sigmas = sqrt((sigmaspool .- wipool .* mu.^2 .+ 2 .* an .* sn) ./ (wipool .+ 2 * an))

        #no longer update beta if it already converged
        if !stopRule(β, beta_old, tol=tol) #(mod(iter_em, 5) == 1 ) & (
            beta_old = copy(β)
            opt = Opt(:LD_LBFGS, J)
            maxeval!(opt, Q_maxiter)
            max_objective!(opt, (beta_new, storage)->Q1(beta_new, storage, X,Y, sample_gamma_mat[:,1:M], facility, llvec, llvecnew))
            (minf,β,ret) = optimize(opt, β)
        end

        if iter_em == maxiteration & maxiteration > 3
            warn("latentgmm not converge!")
        end
        if stopRule(vcat(β, wi, mu, sigmas), vcat(beta_old, wi_old, mu_old, sigmas_old), tol=tol) & (iter_em > initial_iteration)
            #println("latentgmm converged at ", iter_em, "th iteration")
            break
        end

    end

     # xb=X*β
     # llmc = Float64[conditionallikelihood(xb, sample_gamma_mat[:,i], Y, facility) for i in 1:M]
    #m = MixtureModel(map((u, v) -> Normal(u, v), mu, sigmas), wi)

    return(wi, mu, sigmas, β, marginallikelihood(β, X, Y, facility, nF, wi, mu, sigmas, ghx, ghw), sample_gamma_mat[:,1:M]) #+sum(pn(sigmas.^2, sn, an=an))
end

#For fixed wi
function latentgmm_ctau(X::Matrix{Float64}, Y::AbstractArray{Bool, 1}, facility::Vector{Int64}, ncomponent::Int, β_init::Vector{Float64}, wi_init::Vector{Float64}, mu_init::Vector{Float64}, sigmas_init::Vector{Float64}, whichtosplit::Int64, tau::Float64, ghx::Vector{Float64}, ghw::Vector{Float64}; mu_lb::Vector{Float64}=-Inf.*ones(wi_init), mu_ub::Vector{Float64}=Inf.*ones(wi_init), Mmax::Int=5000, M_discard::Int=1000, maxiteration::Int=100, initial_iteration::Int=0, tol::Real=.005, proposingsigma::Float64=1.0, sn::Vector{Float64}=maximum(sigmas_init.^2).*ones(ncomponent), an::Float64=0.25)

    # initialize theta
    N,J=size(X)
    nF = maximum(facility)    
    M = Mmax
    #ncomponent = length(wi_init)
    tau = min(tau, 1-tau)
    wi = copy(wi_init)
    mu = copy(mu_init)
    sigmas = copy(sigmas_init)

    wi_tmp = wi[whichtosplit]+wi[whichtosplit+1]
    wi[whichtosplit] = wi_tmp*tau
    wi[whichtosplit+1] = wi_tmp*(1-tau)
    mu = min(max(mu, mu_lb), mu_ub)    
    wi0=copy(wi) # wi0, mu0 is to store the best parameter
    mu0=copy(mu)
    sigmas0=copy(sigmas)
    β = copy(β_init)
    β0 = copy(β)
    beta_old = randn(J)
    #ghx, ghw = gausshermite(ngh)
    #Preallocate the storage space, reusable for each iteration
    # L_mat = zeros(Int64, (nF, M))
    L = rand(Categorical(wi), nF)
    L_new = rand(Categorical(wi), nF)
    sample_gamma = zeros(nF)
    sample_gamma_new = zeros(nF)
    sample_gamma_mat = zeros(nF, M)
    llvec = zeros(N)
    llvecnew = zeros(N)
    ll_nF = zeros(nF)
    wipool = zeros(ncomponent)
    mupool = zeros(ncomponent)
    sigmaspool = zeros(ncomponent)
    tmp_p=ones(ncomponent) / ncomponent
    ml0=-Inf

    ################################################################################################################
    #iterattion begins here

    no_iter=1
    M = 2000
    Q_maxiter = 2
    lessthanmax = 0
    for iter_em in 1:maxiteration
        if iter_em == (initial_iteration + 1)
            M = Mmax
            Q_maxiter = 10
        end

        for i in 1:nF
            L[i] = rand(Categorical(wi))
            sample_gamma[i] = mean(sample_gamma_mat[i, :]) #rand(Normal(mu[L[i]], sigmas[L[i]])) 
        end        
        fill!(wipool, 0.0)
        fill!(mupool, 0.0)
        fill!(sigmaspool, 0.0)
        @GibbsLgamma
        wi_old=copy(wi)
        mu_old=copy(mu)
        sigmas_old = copy(sigmas)
        #update wi, mu and sigmas
        for j in 1:ncomponent
            if wipool[j] == 0
                wipool[j] = 1
            end
        end
        wi = wipool ./ sum(wipool)
        mu = mupool ./ wipool
        sigmas = sqrt((sigmaspool .- wipool .* mu.^2 .+ 2 .* an .* sn) ./ (wipool .+ 2 * an))

        wi_tmp = wi[whichtosplit]+wi[whichtosplit+1]
        wi[whichtosplit] = wi_tmp*tau
        wi[whichtosplit+1] = wi_tmp*(1-tau)
        mu = min(max(mu, mu_lb), mu_ub)        
        
        #no longer update beta if it already converged
         if !stopRule(β, beta_old, tol=tol) #(mod(iter_em, 5) == 1 ) 
             beta_old = copy(β)
             opt = Opt(:LD_LBFGS, J)
             maxeval!(opt, Q_maxiter)
             max_objective!(opt, (beta_new, storage)->Q1(beta_new, storage, X,Y, sample_gamma_mat[:, 1:M], facility, llvec, llvecnew))
             (minf,β,ret) = optimize(opt, β)
         end

        if iter_em == maxiteration & maxiteration > 20
            warn("latentgmm_ctau not yet converge!")
        end
        ml1 = marginallikelihood(β, X, Y, facility, nF, wi, mu, sigmas, ghx, ghw) + log(2*tau) # + sum(pn(sigmas.^2, sn, an=an))
        if ml1 > ml0
            ml0 = ml1
            mu0=copy(mu)
            sigmas0=copy(sigmas)
            β0 = copy(β)
            lessthanmax = 0
        else
            lessthanmax += 1
        end
        if lessthanmax > 4
            #println("latentgmm_ctau stop at ", iter_em, "th iteration")
            break
        end
        
    end
    #For fixed wi, no need to output gamma_mat
    return(wi0, mu0, sigmas0, β0, ml0)
end

#Starting from 25 initial values, find the best for fixed wi, used as start of the next 2 more iterations
function loglikelihoodratio_ctau(X::Matrix{Float64}, Y::AbstractArray{Bool, 1}, facility::Vector{Int64}, ncomponent1::Int,  betas0::Vector{Float64}, wi_C1::Vector{Float64},  whichtosplit::Int64, tau::Float64, mu_lb::Vector{Float64}, mu_ub::Vector{Float64}, sigmas_lb::Vector{Float64}, sigmas_ub::Vector{Float64}, gamma0::Vector{Float64}; ntrials::Int=25, ngh::Int=1000, sn::Vector{Float64}=sigmas_ub ./ 2, an=.25)

    nF = maximum(facility)
    tau = min(tau, 1-tau)
    ghx, ghw = gausshermite(ngh)
    
    wi = repmat(wi_C1, 1, 4*ntrials)
    mu = zeros(ncomponent1, 4*ntrials)
    sigmas = ones(ncomponent1, 4*ntrials)
    betas = repmat(betas0, 1, 4*ntrials)
    ml = -Inf .* ones(4*ntrials) 
    for i in 1:4*ntrials
        mu[:, i] = rand(ncomponent1) .* (mu_ub .- mu_lb) .+ mu_lb
        sigmas[:, i] = rand(ncomponent1) .* (sigmas_ub .- sigmas_lb) .+ sigmas_lb
        if ncomponent1 != 2
            #fit gmm on gamma_hat with the starting points, to accelerate the latentgmm_ctau
            wi[:, i], mu[:, i], sigmas[:, i], tmp = gmm(gamma0, ncomponent1, wi[:, i], mu[:, i], sigmas[:, i], whichtosplit=whichtosplit, tau=tau, mu_lb=mu_lb,mu_ub=mu_ub, maxiter=1, wifixed=true, sn=sn)
        end
        wi[:, i], mu[:, i], sigmas[:, i], betas[:, i], ml[i] = latentgmm_ctau(X, Y, facility, ncomponent1, betas0, wi[:, i], mu[:, i], sigmas[:, i], whichtosplit, tau, ghx, ghw, mu_lb=mu_lb,mu_ub=mu_ub, maxiteration=8, Mmax=500, M_discard=500, sn=sn, an=an)
    end
    
    mlperm = sortperm(ml)
    for j in 1:ntrials
        i = mlperm[4*ntrials+1 - j] # start from largest ml 
        wi[:, i], mu[:, i], sigmas[:, i], betas[:, i], ml[i] = latentgmm_ctau(X, Y, facility, ncomponent1, betas[:, i], wi[:, i], mu[:, i], sigmas[:, i], whichtosplit, tau, ghx, ghw, mu_lb=mu_lb,mu_ub=mu_ub, maxiteration=100, initial_iteration=0, Mmax=500, M_discard=500, sn=sn, an=an)
    end
    
    mlmax, imax = findmax(ml[mlperm[(3*ntrials+1):4*ntrials]])
    imax = mlperm[3*ntrials+imax]
    
    re=latentgmm(X, Y, facility, ncomponent1, betas[:, imax], wi[:, imax], mu[:, imax], sigmas[:, imax], Mmax=10000, maxiteration=3, initial_iteration=0, an=an, sn=sn)
    
    return(re[1], re[2], re[3], re[4], re[5])
end

function loglikelihoodratio(X::Matrix{Float64}, Y::AbstractArray{Bool, 1}, facility::Vector{Int64}, ncomponent1::Int; vtau::Vector{Float64}=[.5,.3,.1;], ntrials::Int=25, ngh::Int=1000, an::Real=.25)
    C0 = ncomponent1 - 1
    C1 = ncomponent1 
    nF = maximum(facility)

    gamma_init, beta_init, sigmas_tmp = maxposterior(X, Y, facility)
    wi_init, mu_init, sigmas_init, ml_tmp = gmm(gamma_init, C0, ones(C0)/C0, quantile(gamma_init, linspace(0, 1, C0+2)[2:end-1]), ones(C0))

    wi_init, mu_init, sigmas_init, betas_init, ml_C0, gamma_mat = latentgmm(X, Y, facility, C0, beta_init, wi_init, mu_init, sigmas_init, Mmax=10000, initial_iteration=10, maxiteration=150, an=an, sn=var(gamma_init).*ones(C0))
    gamma0 = vec(mean(gamma_mat, 2))    
    mingamma = minimum(gamma0)
    maxgamma = maximum(gamma0)
    
    lr = zeros(length(vtau), C0)
    or = sortperm(mu_init)
    wi0 = wi_init[or]
    mu0 = mu_init[or]
    sigmas0 = sigmas_init[or]
    betas0 = betas_init
    
    for whichtosplit in 1:C0
        ind = [1:whichtosplit, whichtosplit:C0;]
        if C1==2
            mu_lb = mingamma .* ones(2)
            mu_ub = maxgamma .* ones(2)
        elseif C1>2
            mu_lb = [mingamma, (mu0[1:(C0-1)] .+ mu0[2:C0])./2;]
            mu_ub = [(mu0[1:(C0-1)] .+ mu0[2:C0])./2, maxgamma;]
            mu_lb = mu_lb[ind]
            mu_ub = mu_ub[ind]
        end
        sigmas_lb = 0.25 .* sigmas0[ind]
        sigmas_ub = 2 .* sigmas0[ind]
        for i in 1:length(vtau)
            wi_C1 = wi0[ind]
            wi_C1[whichtosplit] = wi_C1[whichtosplit]*vtau[i]
            wi_C1[whichtosplit+1] = wi_C1[whichtosplit+1]*(1-vtau[i])

            wi, mu, sigmas, beta, lr[i, whichtosplit] = loglikelihoodratio_ctau(X, Y, facility, ncomponent1, betas0, wi_C1, whichtosplit, vtau[i], mu_lb, mu_ub,sigmas_lb, sigmas_ub, gamma0, ntrials=ntrials, ngh=ngh, sn=sigmas0[ind].^2, an=an)
        end

    end
    2*(maximum(lr) - ml_C0)  
end

####End of utility functions
