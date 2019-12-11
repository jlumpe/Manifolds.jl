using Random: shuffle!
using StatsBase: AbstractWeights, Weights, values, varcorrection
@doc doc"""
    mean(M,x; weights=Weights(ones(n),n), x0=x[1], stop_iter=100, kwargs... )

computes the Riemannian center of mass also known as Karcher mean of the vector
`x` of `n` points on the [`Manifold`](@ref) `M`. This function
uses the gradient descent scheme. Optionally one can provide
weights $w_i$ for the weighted Riemannian center of mass.
The general formula to compute the minimizer reads
````math
\argmin_{y\in\mathcal M} \frac{1}{2}\sum_{i=1}^n w_i\mathrm{d}_{\mathcal M}^2(y,x_i),
````
where $\mathrm{d}_{\mathcal M}$ denotes the Riemannian [`distance`](@ref).

Optionally you can provide `x0`, the starting point (by default set to the first
data point). `stop_iter` denotes the maximal number of iterations to perform and
the `kwargs...` are passed to [`isapprox`](@ref) to stop, when the inimal change
between two iterates is small. For more stopping criteria
check the [`Manopt.jl`](https://manoptjl.org) package and use a solver therefrom.

The algorithm is further described in 
> Afsari, B; Tron, R.; Vidal, R.: On the Convergence of Gradient
> Descent for Finding the Riemannian Center of Mass,
> SIAM Journal on Control and Optimization (2013), 51(3), pp. 2230–2260, 
> doi: [10.1137/12086282X](https://doi.org/10.1137/12086282X),
> arxiv: [1201.0925](https://arxiv.org/abs/1201.0925)
"""
function mean(M::Manifold, x::AbstractVector, w::AbstractWeights = Weights(ones(length(x)), length(x)); x0 = x[1], kwargs...)
    y = similar_result(M, mean, x0)
    copyto!(y,x0)
    return mean!(M, y, x, w; kwargs...)
end
@doc doc"""
    mean!(M,y,x,w)

computes the [`mean`](@ref) in-place in `y` where the initial value of `y` is
the starting point of the algorithm.
"""
function mean!(M::Manifold, y, x::AbstractVector, w::AbstractWeights = Weights(ones(length(x)), length(x));
            stop_iter=100,
            kwargs...
        ) where {T}
    yold = similar_result(M, mean, y)
    copyto!(yold,y)
    v0 = zero_tangent_vector(M, y)
    v = map(_ -> copy(v0), x)
    #v = zero_tangent_vector.(Ref(M), fill(y,length(x)))
    for i=1:stop_iter
        copyto!(yold,y)
        log!.(Ref(M), v, Ref(yold), x)
        exp!(M, y, yold, sum( values(w).*v ) / 2 )
        isapprox(M,y,yold; kwargs...) && break
    end
    return y
end

@doc doc"""
    median(M,x weights=1/n*ones(n); stop_iter=10000, shuffle=nothing )

computes the Riemannian median of the vector `x`  of `n` points on the
[`Manifold`](@ref) `M`. This function is nonsmooth (i.e nondifferentiable) and
uses a cyclic proximal point scheme. Optionally one can provide
weights $w_i$ for the weighted Riemannian median. The general formula to compute
the minimizer reads
````math
\argmin_{y\in\mathcal M}\sum_{i=1}^n w_i\mathrm{d}_{\mathcal M}(y,x_i),
````
where $\mathrm{d}_{\mathcal M}$ denotes the Riemannian [`distance`](@ref).

The cyclic proximal point can be run with a random cyclic order by setting
`shuffle` to a random number generator, e.g. `GLOBAL_RNG`.

Optionally you can provide `x0`, the starting point (by default set to the first
data point). `stop_iter` denotes the maximal number of iterations to perform and
the `kwargs...` are passed to [`isapprox`](@ref) to stop, when the inimal change
between two iterates is small. For more stopping criteria
check the [`Manopt.jl`](https://manoptjl.org) package and use a solver therefrom.

The algorithm is further described in Algorithm 4.3 and 4.4 in 
> Bačák, M: Computing Medians and Means in Hadamard Spaces.
> SIAM Journal on Optimization (2014), 24(3), pp. 1542–1566,
> doi: [10.1137/140953393](https://doi.org/10.1137/140953393),
> arxiv: [1210.2145](https://arxiv.org/abs/1210.2145)
"""
function median(M::Manifold, x::AbstractVector, w::AbstractWeights = Weights(ones(length(x)), length(x)); x0=x[1], kwargs...)
    y = similar_result(M, median, x[1])
    copyto!(y,x0)
    return median!(M, y, x, w; kwargs...)
end
@doc doc"""
    median!(M,y,x,w)

computes the [`median`](@ref) in-place in `y` where the initial value of `y` is
the starting point of the algorithm.
"""
function median!(M::Manifold, y, x::AbstractVector,
    w::AbstractWeights = Weights(ones(length(x)), length(x));
    stop_iter=100000,
    shuffle_rng = nothing,
    kwargs...
) where {T}
    n = length(x)
    yold = similar_result(M,median,y)
    copyto!(yold,y)
    order = collect(1:n)
    (length(w) != n) && error("The number of weights ($(length(w))) does not math the number of points for the median ($(n)).")
    v = zero_tangent_vector(M,y)
    for i=1:stop_iter
        λ = n/i
        copyto!(yold,y)
        (shuffle_rng != nothing) && shuffle!(shuffle_rng, order)
        for j in order
            @inbounds t = min( λ * w[j]/w.sum, distance(M,y,x[j]) )
            log!(M, v, y, x[j])
            y = exp(M, y, v, t)
        end
        isapprox(M, y, yold; kwargs...) && break
    end
    return y
end

function var(
    M::Manifold,
    x::AbstractVector,
    w::AbstractWeights = Weights(ones(length(x)), length(x)),
    m = nothing;
    corrected::Bool = false,
    kwargs...
)
    if m === nothing
        m = mean(M,x,w; kwargs...)
    end
    wv = convert(Vector, w)
    sqdist = wv .* distance.(Ref(M), Ref(m), x) .^ 2
    s = sum(sqdist)
    if w isa Weights
        n = length(x)
        c = varcorrection(n, corrected) * n / w.sum  # This is what `UnitWeights` is for but not released yet
    else
        c = varcorrection(w, corrected)
    end
    return c * s
end

function var(
    M::Manifold,
    x::AbstractVector,
    mean; kwargs...
)
    n = length(x)
    w = Weights(ones(n), n)
    return var(M, x, w, mean; kwargs...)
end

function std(
    M::Manifold,
    x::AbstractVector,
    w::AbstractWeights,
    mean = mean(M, x, w);
    corrected::Bool = true,
    kwargs...
)
    return sqrt(var(M, x, w, mean; corrected = corrected, kwargs...))
end

function std(
    M::Manifold,
    x::AbstractVector,
    mean = mean(M, x, Weights(ones(length(x)),length(x)));
    corrected::Bool = true,
    kwargs...
)
    return sqrt(var(M, x, mean; corrected = corrected, kwargs...))
end

function mean_and_var(
    M::Manifold,
    x::AbstractVector,
    w::AbstractWeights = Weights(ones(length(x)), length(x));
    kwargs...
)
    m = mean(M, x, w; kwargs...)
    v = var(M, x, w, m; kwargs...)
    return m, v
end

function mean_and_std(
    M::Manifold,
    x::AbstractVector,
    w::AbstractWeights = Weights(ones(length(x)), length(x));
    kwargs...
)
    m = mean(M, x, w; kwargs...)
    s = std(M, x, w, m; kwargs...)
    return m, s
end