## Matrix factorizations and decompositions

abstract Factorization{T}

macro assertposdef(A, info)
   :(($info)==0 ? $A : throw(PosDefException($info)))
end

macro assertnonsingular(A, info)
   :(($info)==0 ? $A : throw(SingularException($info)))
end

##########################
# Cholesky Factorization #
##########################
immutable Cholesky{T} <: Factorization{T}
    UL::Matrix{T}
    uplo::Char
end
immutable CholeskyPivoted{T} <: Factorization{T}
    UL::Matrix{T}
    uplo::Char
    piv::Vector{BlasInt}
    rank::BlasInt
    tol::Real
    info::BlasInt
end

function cholfact!{T<:BlasFloat}(A::StridedMatrix{T}, uplo::Symbol=:U; pivot=false, tol=0.0)
    uplochar = string(uplo)[1]
    if pivot
        A, piv, rank, info = LAPACK.pstrf!(uplochar, A, tol)
        return CholeskyPivoted{T}(A, uplochar, piv, rank, tol, info)
    else
        C, info = LAPACK.potrf!(uplochar, A)
        return @assertposdef Cholesky(C, uplochar) info
    end
end
cholfact{T<:BlasFloat}(A::StridedMatrix{T}, uplo::Symbol=:U; pivot=false, tol=0.0) = cholfact!(copy(A), uplo, pivot=pivot, tol=tol)
cholfact{T}(A::StridedMatrix{T}, uplo::Symbol=:U; pivot=false, tol=0.0) = (S = promote_type(typeof(sqrt(one(T))),Float32); S != T ? cholfact!(convert(Matrix{S},A), uplo, pivot=pivot, tol=tol) : cholfact!(copy(A), uplo, pivot=pivot, tol=tol)) # When julia Cholesky has been implemented, the promotion should be changed.
cholfact(x::Number) = @assertposdef Cholesky(fill(sqrt(x), 1, 1), :U) !(imag(x) == 0 && real(x) > 0)

chol(A::Union(Number, AbstractMatrix), uplo::Symbol) = cholfact(A, uplo)[uplo]
chol(A::Union(Number, AbstractMatrix)) = triu!(cholfact(A, :U).UL)

convert{T,S}(::Type{Cholesky{T}},C::Cholesky{S}) = Cholesky(convert(Matrix{T},C.UL),C.uplo)
convert{T,S}(::Type{CholeskyPivoted{T}},C::CholeskyPivoted{S}) = CholeskyPivoted(convert(Matrix{T},C.UL),C.uplo,C.piv,C.rank,C.tol,C.info)

size(C::Union(Cholesky, CholeskyPivoted)) = size(C.UL)
size(C::Union(Cholesky, CholeskyPivoted), d::Integer) = size(C.UL,d)

function getindex(C::Cholesky, d::Symbol)
    d == :U && return triu!(symbol(C.uplo) == d ? C.UL : C.UL')
    d == :L && return tril!(symbol(C.uplo) == d ? C.UL : C.UL')
    d == :UL && return Triangular(C.UL, symbol(C.uplo))
    throw(KeyError(d))
end
function getindex{T<:BlasFloat}(C::CholeskyPivoted{T}, d::Symbol)
    d == :U && return triu!(symbol(C.uplo) == d ? C.UL : C.UL')
    d == :L && return tril!(symbol(C.uplo) == d ? C.UL : C.UL')
    d == :p && return C.piv
    if d == :P
        n = size(C, 1)
        P = zeros(T, n, n)
        for i=1:n
            P[C.piv[i],i] = one(T)
        end
        return P
    end
    throw(KeyError(d))
end

show(io::IO, C::Cholesky) = (println("$(typeof(C)) with factor:");show(io,C[symbol(C.uplo)]))

A_ldiv_B!{T<:BlasFloat}(C::Cholesky{T}, B::StridedVecOrMat{T}) = LAPACK.potrs!(C.uplo, C.UL, B)
A_ldiv_B!(C::Cholesky, B::StridedVecOrMat) = C.uplo=='L' ? Ac_ldiv_B!(Triangular(C.UL,C.uplo,'N'), A_ldiv_B!(Triangular(C.UL,C.uplo,'N'), B)) : A_ldiv_B!(Triangular(C.UL,C.uplo,'N'), Ac_ldiv_B!(Triangular(C.UL,C.uplo,'N'), B))

function A_ldiv_B!{T<:BlasFloat}(C::CholeskyPivoted{T}, B::StridedVector{T})
    chkfullrank(C)
    ipermute!(LAPACK.potrs!(C.uplo, C.UL, permute!(B, C.piv)), C.piv)
end
function A_ldiv_B!{T<:BlasFloat}(C::CholeskyPivoted{T}, B::StridedMatrix{T})
    chkfullrank(C)
    n = size(C, 1)
    for i=1:size(B, 2)
        permute!(sub(B, 1:n, i), C.piv)
    end
    LAPACK.potrs!(C.uplo, C.UL, B)
    for i=1:size(B, 2)
        ipermute!(sub(B, 1:n, i), C.piv)
    end
    B
end
A_ldiv_B!(C::CholeskyPivoted, B::StridedVector) = C.uplo=='L' ? Ac_ldiv_B!(Triangular(C.UL,C.uplo,'N'), A_ldiv_B!(Triangular(C.UL,C.uplo,'N'), B[C.piv]))[invperm(C.piv)] : A_ldiv_B!(Triangular(C.UL,C.uplo,'N'), Ac_ldiv_B!(Triangular(C.UL,C.uplo,'N'), B[C.piv]))[invperm(C.piv)]
A_ldiv_B!(C::CholeskyPivoted, B::StridedMatrix) = C.uplo=='L' ? Ac_ldiv_B!(Triangular(C.UL,C.uplo,'N'), A_ldiv_B!(Triangular(C.UL,C.uplo,'N'), B[C.piv,:]))[invperm(C.piv),:] : A_ldiv_B!(Triangular(C.UL,C.uplo,'N'), Ac_ldiv_B!(Triangular(C.UL,C.uplo,'N'), B[C.piv,:]))[invperm(C.piv),:]

function det{T}(C::Cholesky{T})
    dd = one(T)
    for i in 1:size(C.UL,1) dd *= abs2(C.UL[i,i]) end
    dd
end

det{T}(C::CholeskyPivoted{T}) = C.rank<size(C.UL,1) ? real(zero(T)) : prod(abs2(diag(C.UL)))

function logdet{T}(C::Cholesky{T})
    dd = zero(T)
    for i in 1:size(C.UL,1) dd += log(C.UL[i,i]) end
    dd + dd # instead of 2.0dd which can change the type
end

inv(C::Cholesky) = copytri!(LAPACK.potri!(C.uplo, copy(C.UL)), C.uplo, true)

function inv(C::CholeskyPivoted)
    chkfullrank(C)
    ipiv = invperm(C.piv)
    copytri!(LAPACK.potri!(C.uplo, copy(C.UL)), C.uplo, true)[ipiv, ipiv]
end

chkfullrank(C::CholeskyPivoted) = C.rank<size(C.UL, 1) && throw(RankDeficientException(C.info))

rank(C::CholeskyPivoted) = C.rank

####################
# LU Factorization #
####################
immutable LU{T} <: Factorization{T}
    factors::Matrix{T}
    ipiv::Vector{BlasInt}
    info::BlasInt
end

lufact!{T<:BlasFloat}(A::StridedMatrix{T}) = LU(LAPACK.getrf!(A)...)
function lufact!{T}(A::AbstractMatrix{T})
    m, n = size(A)
    minmn = min(m,n)
    info = 0
    ipiv = Array(BlasInt, minmn)
    for k = 1:minmn
        # find index max
        kp = 1
        amax = real(zero(T))
        for i = k:m
            absi = abs(A[i,k])
            if absi > amax
                kp = i
                amax = absi
            end
        end
        ipiv[k] = kp
        if A[kp,k] != 0
            # Interchange
            for i = 1:n
                tmp = A[k,i]
                A[k,i] = A[kp,i]
                A[kp,i] = tmp
            end
            # Scale first column
            Akkinv = inv(A[k,k])
            for i = k+1:m
                A[i,k] *= Akkinv
            end
        elseif info == 0
            info = k
        end
        # Update the rest
        for j = k+1:n
            for i = k+1:m
                A[i,j] -= A[i,k]*A[k,j]
            end
        end
    end
    if minmn > 0 && A[minmn,minmn] == 0; info = minmn; end
    LU(A, ipiv, convert(BlasInt, info))
end
lufact{T<:BlasFloat}(A::StridedMatrix{T}) = lufact!(copy(A))
lufact{T}(A::StridedMatrix{T}) = (S = typeof(one(T)/one(T)); S != T ? lufact!(convert(Matrix{S}, A)) : lufact!(copy(A)))
lufact(x::Number) = LU(fill(x, 1, 1), BlasInt[1], x == 0 ? one(BlasInt) : zero(BlasInt))

function lu(A::Union(Number, AbstractMatrix))
    F = lufact(A)
    F[:L], F[:U], F[:p]
end

convert{T}(::Type{LU{T}}, F::LU) = LU(convert(Matrix{T}, F.factors), F.ipiv, F.info)

size(A::LU) = size(A.factors)
size(A::LU,n) = size(A.factors,n)

function ipiv2perm{T}(v::AbstractVector{T}, maxi::Integer)
    p = T[1:maxi]
    @inbounds for i in 1:length(v)
        p[i], p[v[i]] = p[v[i]], p[i]
    end
    return p
end

function getindex{T}(A::LU{T}, d::Symbol)
    m, n = size(A)
    d == :L && return tril(A.factors[1:m, 1:min(m,n)], -1) + eye(T, m, min(m,n))
    d == :U && return triu(A.factors[1:min(m,n),1:n])
    d == :p && return ipiv2perm(A.ipiv, m)
    if d == :P
        p = A[:p]
        P = zeros(T, m, m)
        for i in 1:m
            P[i,p[i]] = one(T)
        end
        return P
    end
    throw(KeyError(d))
end

function det{T}(A::LU{T})
    n = chksquare(A)
    A.info > 0 && return zero(typeof(A.factors[1]))
    return prod(diag(A.factors)) * (bool(sum(A.ipiv .!= 1:n) % 2) ? -one(T) : one(T))
end

function logdet2{T<:Real}(A::LU{T})  # return log(abs(det)) and sign(det)
    n = chksquare(A)
    dg = diag(A.factors)
    s = (bool(sum(A.ipiv .!= 1:n) % 2) ? -one(T) : one(T)) * prod(sign(dg))
    sum(log(abs(dg))), s 
end

function logdet{T<:Real}(A::LU{T})
    d,s = logdet2(A)
    s>=0 || error("DomainError: determinant is negative")
    d
end

function logdet{T<:Complex}(A::LU{T})
    n = chksquare(A)
    s = sum(log(diag(A.factors))) + (bool(sum(A.ipiv .!= 1:n) % 2) ? complex(0,pi) : 0) 
    r, a = reim(s)
    a = pi-mod(pi-a,2pi) #Take principal branch with argument (-pi,pi] 
    complex(r,a)    
end

A_ldiv_B!{T<:BlasFloat}(A::LU{T}, B::StridedVecOrMat{T}) = @assertnonsingular LAPACK.getrs!('N', A.factors, A.ipiv, B) A.info
A_ldiv_B!(A::LU, b::StridedVector) = A_ldiv_B!(Triangular(A.factors, :U, false), A_ldiv_B!(Triangular(A.factors, :L, true), b[ipiv2perm(A.ipiv, length(b))]))
A_ldiv_B!(A::LU, B::StridedMatrix) = A_ldiv_B!(Triangular(A.factors, :U, false), A_ldiv_B!(Triangular(A.factors, :L, true), B[ipiv2perm(A.ipiv, size(B, 1)),:]))
At_ldiv_B{T<:BlasFloat}(A::LU{T}, B::StridedVecOrMat{T}) = @assertnonsingular LAPACK.getrs!('T', A.factors, A.ipiv, copy(B)) A.info
Ac_ldiv_B{T<:BlasComplex}(A::LU{T}, B::StridedVecOrMat{T}) = @assertnonsingular LAPACK.getrs!('C', A.factors, A.ipiv, copy(B)) A.info
At_ldiv_Bt{T<:BlasFloat}(A::LU{T}, B::StridedVecOrMat{T}) = @assertnonsingular LAPACK.getrs!('T', A.factors, A.ipiv, transpose(B)) A.info
Ac_ldiv_Bc{T<:BlasComplex}(A::LU{T}, B::StridedVecOrMat{T}) = @assertnonsingular LAPACK.getrs!('C', A.factors, A.ipiv, ctranspose(B)) A.info

/{T}(B::Matrix{T},A::LU{T}) = At_ldiv_Bt(A,B).'

inv{T<:BlasFloat}(A::LU{T})=@assertnonsingular LAPACK.getri!(copy(A.factors), A.ipiv) A.info

cond(A::LU, p) = inv(LAPACK.gecon!(p == 1 ? '1' : 'I', A.factors, norm(A[:L][A[:p],:]*A[:U], p)))

####################
# QR Factorization #
####################

immutable QR{T} <: Factorization{T}
    factors::Matrix{T}
    τ::Vector{T}
end
# Note. For QRCompactWY factorization without pivoting, the WY representation based method introduced in LAPACK 3.4
immutable QRCompactWY{S} <: Factorization{S}
    factors::Matrix{S}
    T::Matrix{S}
end

immutable QRPivoted{T} <: Factorization{T}
    factors::Matrix{T}
    τ::Vector{T}
    jpvt::Vector{BlasInt}
end

qrfact!{T<:BlasFloat}(A::StridedMatrix{T}; pivot=false) = pivot ? QRPivoted{T}(LAPACK.geqp3!(A)...) : QRCompactWY(LAPACK.geqrt!(A, min(minimum(size(A)), 36))...)
function qrfact!{T}(A::AbstractMatrix{T}; pivot=false)
    pivot && warn("pivoting only implemented for Float32, Float64, Complex64 and Complex128")
    m, n = size(A)
    τ = zeros(T, min(m,n))
    @inbounds begin
        for k = 1:min(m-1+!(T<:Real),n)
            τk = elementaryLeft!(A, k, k)
            τ[k] = τk
            for j = k+1:n
                νAj = A[k,j]
                for i = k+1:m
                    νAj += conj(A[i,k])*A[i,j]
                end
                νAj *= conj(τk)
                A[k,j] -= νAj
                for i = k+1:m
                    A[i,j] -= A[i,k]*νAj
                end
            end
        end
    end
    QR(A, τ)
end
qrfact{T<:BlasFloat}(A::StridedMatrix{T}; pivot=false) = qrfact!(copy(A),pivot=pivot)
qrfact{T}(A::StridedMatrix{T}; pivot=false) = (S = typeof(one(T)/norm(one(T)));S != T ? qrfact!(convert(Matrix{S},A), pivot=pivot) : qrfact!(copy(A),pivot=pivot))
qrfact(x::Number) = qrfact(fill(x,1,1))

function qr(A::Union(Number, AbstractMatrix); pivot=false, thin::Bool=true)
    F = qrfact(A, pivot=pivot)
    full(F[:Q], thin=thin), F[:R]
end

convert{T}(::Type{QR{T}},A::QR) = QR(convert(Matrix{T}, A.factors), convert(Vector{T}, A.τ))
convert{T}(::Type{QRCompactWY{T}},A::QRCompactWY) = QRCompactWY(convert(Matrix{T}, A.factors), convert(Matrix{T}, A.T))
convert{T}(::Type{QRPivoted{T}},A::QRPivoted) = QRPivoted(convert(Matrix{T}, A.factors), convert(Vector{T}, A.τ), A.jpvt)

function getindex(A::QR, d::Symbol)
    d == :R && return triu(A.factors[1:minimum(size(A)),:])
    d == :Q && return QRPackedQ(A.factors,A.τ)
    throw(KeyError(d))
end
function getindex(A::QRCompactWY, d::Symbol)
    d == :R && return triu(A.factors[1:minimum(size(A)),:])
    d == :Q && return QRCompactWYQ(A.factors,A.T)
    throw(KeyError(d))
end
function getindex{T}(A::QRPivoted{T}, d::Symbol)
    d == :R && return triu(A.factors[1:minimum(size(A)),:])
    d == :Q && return QRPackedQ(A.factors,A.τ)
    d == :p && return A.jpvt
    if d == :P
        p = A[:p]
        n = length(p)
        P = zeros(T, n, n)
        for i in 1:n
            P[p[i],i] = one(T)
        end
        return P
    end
    throw(KeyError(d))
end

immutable QRPackedQ{T} <: AbstractMatrix{T}
    factors::Matrix{T}
    τ::Vector{T}
end
immutable QRCompactWYQ{S} <: AbstractMatrix{S} 
    factors::Matrix{S}                      
    T::Matrix{S}                       
end

convert{T,S}(::Type{QRPackedQ{T}}, Q::QRPackedQ{S}) = QRPackedQ(convert(Matrix{T}, Q.factors), convert(Vector{T}, Q.τ))
convert{S1,S2}(::Type{QRCompactWYQ{S1}}, Q::QRCompactWYQ{S2}) = QRCompactWYQ(convert(Matrix{S1}, Q.factors), convert(Matrix{S1}, Q.T))

size(A::Union(QR,QRCompactWY,QRPivoted), dim::Integer) = size(A.factors, dim)
size(A::Union(QR,QRCompactWY,QRPivoted)) = size(A.factors)
size(A::Union(QRPackedQ,QRCompactWYQ), dim::Integer) = 0 < dim ? (dim <= 2 ? size(A.factors, 1) : 1) : throw(BoundsError())
size(A::Union(QRPackedQ,QRCompactWYQ)) = size(A, 1), size(A, 2)

full{T}(A::Union(QRPackedQ{T},QRCompactWYQ{T}); thin::Bool=true) = A_mul_B!(A, thin ? eye(T, size(A.factors)...) : eye(T, size(A.factors,1)))

print_matrix(io::IO, A::Union(QRPackedQ,QRCompactWYQ), rows::Integer, cols::Integer) = print_matrix(io, full(A, thin=false), rows, cols)

## Multiplication by Q
### QB
A_mul_B!{T<:BlasFloat}(A::QRCompactWYQ{T}, B::StridedVecOrMat{T}) = LAPACK.gemqrt!('L','N',A.factors,A.T,B)
A_mul_B!{T<:BlasFloat}(A::QRPackedQ{T}, B::StridedVecOrMat{T}) = LAPACK.ormqr!('L','N',A.factors,A.τ,B)
function A_mul_B!{T}(A::QRPackedQ{T}, B::AbstractVecOrMat{T})
    mA, nA = size(A.factors)
    mB, nB = size(B,1), size(B,2)
    mA == mB || throw(DimensionMismatch(""))
    Afactors = A.factors
    @inbounds begin
        for k = min(mA,nA):-1:1
            for j = 1:nB
                νBj = B[k,j]
                for i = k+1:mB
                    νBj += conj(Afactors[i,k])*B[i,j]
                end
                νBj *= conj(A.τ[k])
                B[k,j] -= νBj
                for i = k+1:mB
                    B[i,j] -= Afactors[i,k]*νBj
                end
            end
        end
    end
    B
end
function *{TA,Tb}(A::Union(QRPackedQ{TA},QRCompactWYQ{TA}), b::StridedVector{Tb})
    TAb = promote_type(TA,Tb)
    Anew = convert(typeof(A).name.primary{TAb},A)
    bnew = size(A.factors,1) == length(b) ? (Tb == TAb ? copy(b) : convert(Vector{TAb}, b)) : (size(A.factors,2) == length(b) ? [b,zeros(TAb, size(A.factors,1)-length(b))] : throw(DimensionMismatch("")))
    A_mul_B!(Anew,bnew)
end
function *{TA,TB}(A::Union(QRPackedQ{TA},QRCompactWYQ{TA}), B::StridedMatrix{TB})
    TAB = promote_type(TA,TB)
    Anew = convert(typeof(A).name.primary{TAB},A)
    Bnew = size(A.factors,1) == size(B,1) ? (TB == TAB ? copy(B) : convert(Matrix{TAB}, B)) : (size(A.factors,2) == size(B,1) ? [B;zeros(TAB, size(A.factors,1)-size(B,1),size(B,2))] : throw(DimensionMismatch("")))
    A_mul_B!(Anew,Bnew)
end
### QcB
Ac_mul_B!{T<:BlasReal}(A::QRCompactWYQ{T}, B::StridedVecOrMat{T}) = LAPACK.gemqrt!('L','T',A.factors,A.T,B)
Ac_mul_B!{T<:BlasComplex}(A::QRCompactWYQ{T}, B::StridedVecOrMat{T}) = LAPACK.gemqrt!('L','C',A.factors,A.T,B)
Ac_mul_B!{T<:BlasReal}(A::QRPackedQ{T}, B::StridedVecOrMat{T}) = LAPACK.ormqr!('L','T',A.factors,A.τ,B)
Ac_mul_B!{T<:BlasComplex}(A::QRPackedQ{T}, B::StridedVecOrMat{T}) = LAPACK.ormqr!('L','C',A.factors,A.τ,B)
function Ac_mul_B!{T}(A::QRPackedQ{T}, B::AbstractVecOrMat{T})
    mA, nA = size(A.factors)
    mB, nB = size(B,1), size(B,2)
    mA == mB || throw(DimensionMismatch(""))
    Afactors = A.factors
    @inbounds begin
        for k = 1:min(mA,nA)
            for j = 1:nB
                νBj = B[k,j]
                for i = k+1:mB
                    νBj += conj(Afactors[i,k])*B[i,j]
                end
                νBj *= A.τ[k]
                B[k,j] -= νBj
                for i = k+1:mB
                    B[i,j] -= Afactors[i,k]*νBj
                end
            end
        end
    end
    B
end
function Ac_mul_B{TQ<:Number,TB<:Number}(Q::Union(QRPackedQ{TQ},QRCompactWYQ{TQ}), B::StridedVecOrMat{TB})
    TQB = promote_type(TQ,TB)
    Ac_mul_B!(convert(typeof(Q).name.primary{TQB}, Q), TB == TQB ? copy(B) : convert(typeof(B).name.primary{TQB}, B))
end
### AQ
A_mul_B!{T<:BlasFloat}(A::StridedVecOrMat{T}, B::QRCompactWYQ{T}) = LAPACK.gemqrt!('R','N', B.factors, B.T, A)
A_mul_B!(A::StridedVecOrMat, B::QRPackedQ) = LAPACK.ormqr!('R', 'N', B.factors, B.τ, A)
function A_mul_B!{T}(A::StridedMatrix{T},Q::QRPackedQ{T})
    mQ, nQ = size(Q.factors)
    mA, nA = size(A,1), size(A,2)
    nA == mQ || throw(DimensionMismatch(""))
    Qfactors = Q.factors
    @inbounds begin
        for k = 1:min(mQ,nQ)
            for i = 1:mA
                νAi = A[i,k]
                for j = k+1:mQ
                    νAi += Qfactors[j,k]*A[i,j]
                end
                νAi *= conj(Q.τ[k])
                A[i,k] -= νAi
                for j = k+1:nA
                    A[i,j] -= Qfactors[j,k]*νAi
                end
            end
        end
    end
    A
end
function *{TA,TQ}(A::StridedVecOrMat{TA}, Q::Union(QRPackedQ{TQ},QRCompactWYQ{TQ}))
    TAQ = promote_type(TA, TQ)
    A_mul_B!(TA==TAQ ? copy(A) : convert(typeof(A).name.primary{TAQ}, A), convert(typeof(Q).name.primary{TAQ}, Q))
end
### AQc
A_mul_Bc!{T<:BlasReal}(A::StridedVecOrMat{T}, B::QRCompactWYQ{T}) = LAPACK.gemqrt!('R','T',B.factors,B.T,A)
A_mul_Bc!{T<:BlasComplex}(A::StridedVecOrMat{T}, B::QRCompactWYQ{T}) = LAPACK.gemqrt!('R','C',B.factors,B.T,A)
A_mul_Bc!{T<:BlasReal}(A::StridedVecOrMat{T}, B::QRPackedQ{T}) = LAPACK.ormqr!('R','T',B.factors,B.τ,A)
A_mul_Bc!{T<:BlasComplex}(A::StridedVecOrMat{T}, B::QRPackedQ{T}) = LAPACK.ormqr!('R','C',B.factors,B.τ,A)
function A_mul_Bc!{T}(A::AbstractMatrix{T},Q::QRPackedQ{T})
    mQ, nQ = size(Q.factors)
    mA, nA = size(A,1), size(A,2)
    nA == mQ || throw(DimensionMismatch(""))
    Qfactors = Q.factors
    @inbounds begin
        for k = min(mQ,nQ):-1:1
            for i = 1:mA
                νAi = A[i,k]
                for j = k+1:mQ
                    νAi += Qfactors[j,k]*A[i,j]
                end
                νAi *= Q.τ[k]
                A[i,k] -= νAi
                for j = k+1:nA
                    A[i,j] -= Qfactors[j,k]*νAi
                end
            end
        end
    end
    A
end
function A_mul_Bc{TA,TB}(A::AbstractVecOrMat{TA}, B::Union(QRCompactWYQ{TB},QRPackedQ{TB}))
    TAB = promote_type(TA,TB)
    A_mul_Bc!(size(A,2)==size(B.factors,1) ? copy(A) : (size(A,2)==size(B.factors,2) ? [A zeros(T, size(A, 1), size(B.factors, 1) - size(B.factors, 2))] : throw(DimensionMismatch(""))))
end

# Julia implementation similarly to xgelsy
function A_ldiv_B!{T<:BlasFloat}(A::Union(QRCompactWY{T},QRPivoted{T}), B::StridedMatrix{T}, rcond::Real)
    mA, nA = size(A.factors)
    nr = min(mA,nA)
    nrhs = size(B, 2)
    if nr == 0 return zeros(0, nrhs), 0 end
    ar = abs(A.factors[1])
    if ar == 0 return zeros(nr, nrhs), 0 end
    rnk = 1
    xmin = ones(T, nr)
    xmax = ones(T, nr)
    tmin = tmax = ar
    while rnk < nr
        tmin, smin, cmin = LAPACK.laic1!(2, sub(xmin, 1:rnk), tmin, sub(A.factors, 1:rnk, rnk + 1), A.factors[rnk + 1, rnk + 1])
        tmax, smax, cmax = LAPACK.laic1!(1, sub(xmax, 1:rnk), tmax, sub(A.factors, 1:rnk, rnk + 1), A.factors[rnk + 1, rnk + 1])
        tmax*rcond > tmin && break
        xmin[1:rnk + 1] = [smin*sub(xmin, 1:rnk), cmin]
        xmax[1:rnk + 1] = [smax*sub(xmin, 1:rnk), cmax]
        rnk += 1
        # if cond(r[1:rnk, 1:rnk])*rcond < 1 break end
    end
    C, τ = LAPACK.tzrzf!(A.factors[1:rnk,:])
    A_ldiv_B!(Triangular(C[1:rnk,1:rnk],:U),sub(Ac_mul_B!(A[:Q],sub(B, 1:mA, 1:nrhs)),1:rnk,1:nrhs))
    B[rnk+1:end,:] = zero(T)
    LAPACK.ormrz!('L', iseltype(B, Complex) ? 'C' : 'T', C, τ, sub(B,1:nA,1:nrhs))
    return isa(A,QRPivoted) ? B[invperm(A[:p]),:] : B[1:nA,:], rnk
end
A_ldiv_B!{T<:BlasFloat}(A::Union(QRCompactWY{T},QRPivoted{T}), B::StridedVector{T}) = A_ldiv_B!(A,reshape(B,length(B),1))[:]
A_ldiv_B!{T<:BlasFloat}(A::Union(QRCompactWY{T},QRPivoted{T}), B::StridedVecOrMat{T}) = A_ldiv_B!(A, B, sqrt(eps(real(float(one(eltype(B)))))))[1]
function A_ldiv_B!{T}(A::QR{T},B::StridedMatrix{T})
    m, n = size(A)
    minmn = min(m,n)
    mB, nB = size(B)
    Ac_mul_B!(A[:Q],sub(B,1:m,1:nB)) # Reconsider when arrayviews are merged.
    R = A[:R]
    @inbounds begin
        if n > m # minimum norm solution
            τ = zeros(T,m)
            for k = m:-1:1 # Trapezoid to triangular by elementary operation
                τ[k] = elementaryRightTrapezoid!(R,k)
                for i = 1:k-1
                    νRi = R[i,k]
                    for j = m+1:n
                        νRi += R[i,j]*R[k,j]
                    end
                    νRi *= τ[k]
                    R[i,k] -= νRi
                    for j = m+1:n
                        R[i,j] -= νRi*R[k,j]
                    end
                end
            end
        end
        for k = 1:nB # solve triangular system. When array views are implemented, consider exporting    to function.
            for i = minmn:-1:1
                for j = i+1:minmn
                    B[i,k] -= R[i,j]*B[j,k]
                end
                B[i,k] /= R[i,i]
            end
        end
        if n > m # Apply elemenary transformation to solution
            B[m+1:mB,1:nB] = zero(T)
            for j = 1:nB
                for k = 1:m
                    νBj = B[k,j]
                    for i = m+1:n
                        νBj += B[i,j]*conj(R[k,i])
                    end
                    νBj *= τ[k]
                    B[k,j] -= νBj
                    for i = m+1:n
                        B[i,j] -= R[k,i]*νBj
                    end
                end
            end
        end
    end
    return B[1:n,:]
end
A_ldiv_B!(A::QR, B::StridedVector) = A_ldiv_B!(A, reshape(B, length(B), 1))[:]
A_ldiv_B!(A::QRPivoted, B::StridedVector) = A_ldiv_B!(QR(A.factors,A.τ),B)[invperm(A.jpvt)]
A_ldiv_B!(A::QRPivoted, B::StridedMatrix) = A_ldiv_B!(QR(A.factors,A.τ),B)[invperm(A.jpvt),:]
function \{TA,TB}(A::Union(QR{TA},QRCompactWY{TA},QRPivoted{TA}),B::StridedVector{TB})
    S = promote_type(TA,TB)
    m,n = size(A)
    n > m ? A_ldiv_B!(convert(typeof(A).name.primary{S},A),[B,zeros(S,n-m)]) : A_ldiv_B!(convert(typeof(A).name.primary{S},A), S == TB ? copy(B) : convert(Vector{S}, B))
end
function \{TA,TB}(A::Union(QR{TA},QRCompactWY{TA},QRPivoted{TA}),B::StridedMatrix{TB})
    S = promote_type(TA,TB)
    m,n = size(A)
    n > m ? A_ldiv_B!(convert(typeof(A).name.primary{S},A),[B;zeros(S,n-m,size(B,2))]) : A_ldiv_B!(convert(typeof(A).name.primary{S},A), S == TB ? copy(B) : convert(Matrix{S}, B))
end

##TODO:  Add methods for rank(A::QRP{T}) and adjust the (\) method accordingly
##       Add rcond methods for Cholesky, LU, QR and QRP types
## Lower priority: Add LQ, QL and RQ factorizations

# FIXME! Should add balancing option through xgebal
immutable Hessenberg{T} <: Factorization{T}
    factors::Matrix{T}
    τ::Vector{T}
end
Hessenberg(A::StridedMatrix) = Hessenberg(LAPACK.gehrd!(A)...)

hessfact!{T<:BlasFloat}(A::StridedMatrix{T}) = Hessenberg(A)
hessfact{T<:BlasFloat}(A::StridedMatrix{T}) = hessfact!(copy(A))
hessfact{T}(A::StridedMatrix{T}) = (S = promote_type(Float32,typeof(one(T)/norm(one(T)))); S != T ? hessfact!(convert(Matrix{S},A)) : hessfact!(copy(A)))

immutable HessenbergQ{T} <: AbstractMatrix{T}
    factors::Matrix{T}
    τ::Vector{T}
end
HessenbergQ(A::Hessenberg) = HessenbergQ(A.factors, A.τ)
size(A::HessenbergQ, args...) = size(A.factors, args...)
getindex(A::HessenbergQ, i::Real) = getindex(full(A), i)
getindex(A::HessenbergQ, i::AbstractArray) = getindex(full(A), i)
getindex(A::HessenbergQ, args...) = getindex(full(A), args...)

function getindex(A::Hessenberg, d::Symbol)
    d == :Q && return HessenbergQ(A)
    d == :H && return triu(A.factors, -1)
    throw(KeyError(d))
end

full(A::HessenbergQ) = LAPACK.orghr!(1, size(A.factors, 1), copy(A.factors), A.τ)

#######################
# Eigendecompositions #
#######################

# Eigenvalues
immutable Eigen{T,V} <: Factorization{T}
    values::Vector{V}
    vectors::Matrix{T}
end

# Generalized eigenvalue problem.
immutable GeneralizedEigen{T,V} <: Factorization{T}
    values::Vector{V}
    vectors::Matrix{T}
end

function getindex(A::Union(Eigen,GeneralizedEigen), d::Symbol)
    d == :values && return A.values
    d == :vectors && return A.vectors
    throw(KeyError(d))
end

isposdef(A::Union(Eigen,GeneralizedEigen)) = all(A.values .> 0)

function eigfact!{T<:BlasReal}(A::StridedMatrix{T}; permute::Bool=true, scale::Bool=true)
    n = size(A, 2)
    n==0 && return Eigen(zeros(T, 0), zeros(T, 0, 0))
    issym(A) && return eigfact!(Symmetric(A))
    A, WR, WI, VL, VR, _ = LAPACK.geevx!(permute ? (scale ? 'B' : 'P') : (scale ? 'S' : 'N'), 'N', 'V', 'N', A)
    all(WI .== 0.) && return Eigen(WR, VR)
    evec = zeros(Complex{T}, n, n)
    j = 1
    while j <= n
        if WI[j] == 0.0
            evec[:,j] = VR[:,j]
        else
            evec[:,j]   = VR[:,j] + im*VR[:,j+1]
            evec[:,j+1] = VR[:,j] - im*VR[:,j+1]
            j += 1
        end
        j += 1
    end
    return Eigen(complex(WR, WI), evec)
end

function eigfact!{T<:BlasComplex}(A::StridedMatrix{T}; permute::Bool=true, scale::Bool=true)
    n = size(A, 2)
    n == 0 && return Eigen(zeros(T, 0), zeros(T, 0, 0))
    ishermitian(A) && return eigfact!(Hermitian(A)) 
    return Eigen(LAPACK.geevx!(permute ? (scale ? 'B' : 'P') : (scale ? 'S' : 'N'), 'N', 'V', 'N', A)[[2,4]]...)
end
eigfact{T<:BlasFloat}(A::StridedMatrix{T}; kwargs...) = eigfact!(copy(A); kwargs...)
eigfact{T}(A::StridedMatrix{T}; kwargs...) = (S = promote_type(Float32,typeof(one(T)/norm(one(T)))); S != T ? eigfact!(convert(Matrix{S}, A); kwargs...) : eigfact!(copy(A); kwargs...))
eigfact(x::Number) = Eigen([x], fill(one(x), 1, 1))

# function eig(A::Union(Number, AbstractMatrix); permute::Bool=true, scale::Bool=true)
#     F = eigfact(A, permute=permute, scale=scale)
#     F[:values], F[:vectors]
# end
function eig(A::Union(Number, AbstractMatrix); kwargs...)
    F = eigfact(A, kwargs...)
    F[:values], F[:vectors]
end
#Calculates eigenvectors
eigvecs(A::Union(Number, AbstractMatrix); kwargs...) = eigfact(A; kwargs...)[:vectors]

function eigvals!{T<:BlasReal}(A::StridedMatrix{T}; permute::Bool=true, scale::Bool=true)
    issym(A) && return eigvals!(Symmetric(A))
    _, valsre, valsim, _ = LAPACK.geevx!(permute ? (scale ? 'B' : 'P') : (scale ? 'S' : 'N'), 'N', 'N', 'N', A)
    return all(valsim .== 0) ? valsre : complex(valsre, valsim)
end
function eigvals!{T<:BlasComplex}(A::StridedMatrix{T}; permute::Bool=true, scale::Bool=true)
    ishermitian(A) && return eigvals(Hermitian(A))
    return LAPACK.geevx!(permute ? (scale ? 'B' : 'P') : (scale ? 'S' : 'N'), 'N', 'N', 'N', A)[2]
end
eigvals{T<:BlasFloat}(A::StridedMatrix{T}; kwargs...) = eigvals!(copy(A); kwargs...)
eigvals{T}(A::AbstractMatrix{T}; kwargs...) = (S = promote_type(Float32,typeof(one(T)/norm(one(T)))); S != T ? eigvals!(convert(Matrix{S}, A); kwargs...) : eigvals!(copy(A); kwargs...))

eigvals{T<:Number}(x::T; kwargs...) = (val = convert(promote_type(Float32,typeof(one(T)/norm(one(T)))),x); imag(val) == 0 ? [real(val)] : [val])

#Computes maximum and minimum eigenvalue
function eigmax(A::Union(Number, AbstractMatrix); kwargs...)
    v = eigvals(A; kwargs...)
    iseltype(v,Complex) ? error("DomainError: complex eigenvalues cannot be ordered") : maximum(v)
end
function eigmin(A::Union(Number, AbstractMatrix); kwargs...)
    v = eigvals(A; kwargs...)
    iseltype(v,Complex) ? error("DomainError: complex eigenvalues cannot be ordered") : minimum(v)
end

inv(A::Eigen) = scale(A.vectors, 1.0/A.values)*A.vectors'
det(A::Eigen) = prod(A.values)

# Generalized eigenproblem
function eigfact!{T<:BlasReal}(A::StridedMatrix{T}, B::StridedMatrix{T})
    issym(A) && issym(B) && return eigfact!(Symmetric(A), Symmetric(B))
    n = size(A, 1)
    alphar, alphai, beta, _, vr = LAPACK.ggev!('N', 'V', A, B)
    all(alphai .== 0) && return GeneralizedEigen(alphar ./ beta, vr)

    vecs = zeros(Complex{T}, n, n)
    j = 1
    while j <= n
        if alphai[j] == 0.0
            vecs[:,j] = vr[:,j]
        else
            vecs[:,j  ] = vr[:,j] + im*vr[:,j+1]
            vecs[:,j+1] = vr[:,j] - im*vr[:,j+1]
            j += 1
        end
        j += 1
    end
    return GeneralizedEigen(complex(alphar, alphai)./beta, vecs)
end

function eigfact!{T<:BlasComplex}(A::StridedMatrix{T}, B::StridedMatrix{T})
    ishermitian(A) && ishermitian(B) && return eigfact!(Hermitian(A), Hermitian(B))
    alpha, beta, _, vr = LAPACK.ggev!('N', 'V', A, B)
    return GeneralizedEigen(alpha./beta, vr)
end
eigfact{T<:BlasFloat}(A::AbstractMatrix{T}, B::StridedMatrix{T}) = eigfact!(copy(A),copy(B))
eigfact{TA,TB}(A::AbstractMatrix{TA}, B::AbstractMatrix{TB}) = (S = promote_type(Float32,typeof(one(TA)/norm(one(TA))),TB); eigfact!(S != TA ? convert(Matrix{S},A) : copy(A), S != TB ? convert(Matrix{S},B) : copy(B)))

function eig(A::AbstractMatrix, B::AbstractMatrix)
    F = eigfact(A, B)
    F[:values], F[:vectors]
end

function eigvals!{T<:BlasReal}(A::StridedMatrix{T}, B::StridedMatrix{T})
    issym(A) && issym(B) && return eigvals!(Symmetric(A), Symmetric(B))
    alphar, alphai, beta, vl, vr = LAPACK.ggev!('N', 'N', A, B)
    (all(alphai .== 0) ? alphar : complex(alphar, alphai))./beta
end
function eigvals!{T<:BlasComplex}(A::StridedMatrix{T}, B::StridedMatrix{T})
    ishermitian(A) && ishermitian(B) && return eigvals!(Hermitian(A), Hermitian(B))
    alpha, beta, vl, vr = LAPACK.ggev!('N', 'N', A, B)
    alpha./beta
end
eigvals{T<:BlasFloat}(A::StridedMatrix{T},B::StridedMatrix{T}) = eigvals!(copy(A),copy(B))
eigvals{TA,TB}(A::AbstractMatrix{TA}, B::AbstractMatrix{TB}) = (S = promote_type(Float32,typeof(one(TA)/norm(one(TA))),TB); eigvals!(S != TA ? convert(Matrix{S},A) : copy(A), S != TB ? convert(Matrix{S},B) : copy(B)))

# SVD
immutable SVD{T<:BlasFloat,Tr} <: Factorization{T}
    U::Matrix{T}
    S::Vector{Tr}
    Vt::Matrix{T}
end
function svdfact!{T<:BlasFloat}(A::StridedMatrix{T}; thin::Bool=true)
    m,n = size(A)
    if m == 0 || n == 0
        u,s,vt = (eye(T, m, thin ? n : m), real(zeros(T,0)), eye(T,n,n))
    else
        u,s,vt = LAPACK.gesdd!(thin ? 'S' : 'A', A)
    end
    SVD(u,s,vt)
end
svdfact{T<:BlasFloat}(A::StridedMatrix{T};thin=true) = svdfact!(copy(A),thin=thin)
svdfact{T}(A::StridedVecOrMat{T};thin=true) = (S = promote_type(Float32,typeof(one(T)/norm(one(T)))); S != T ? svdfact!(convert(Matrix{S},A),thin=thin) : svdfact!(copy(A),thin=thin))
svdfact(x::Number; thin::Bool=true) = SVD(x == 0 ? fill(one(x), 1, 1) : fill(x/abs(x), 1, 1), [abs(x)], fill(one(x), 1, 1))
svdfact(x::Integer; thin::Bool=true) = svdfact(float(x), thin=thin)

function svd(A::Union(Number, AbstractArray); thin::Bool=true)
    F = svdfact(A, thin=thin)
    F.U, F.S, F.Vt'
end

function getindex(F::SVD, d::Symbol)
    d == :U && return F.U
    d == :S && return F.S
    d == :Vt && return F.Vt
    d == :V && return F.Vt'
    throw(KeyError(d))
end

svdvals!{T<:BlasFloat}(A::StridedMatrix{T}) = any([size(A)...].==0) ? zeros(T, 0) : LAPACK.gesdd!('N', A)[2]
svdvals{T<:BlasFloat}(A::StridedMatrix{T}) = svdvals!(copy(A))
svdvals{T}(A::StridedMatrix{T}) = (S = promote_type(Float32,typeof(one(T)/norm(one(T)))); S != T ? svdvals!(convert(Matrix{S}, A)) : svdvals!(copy(A)))
svdvals(x::Number) = [abs(x)]

# SVD least squares
function \{T<:BlasFloat}(A::SVD{T}, B::StridedVecOrMat{T})
    n = length(A.S)
    Sinv = zeros(T, n)
    Sinv[A.S .> sqrt(eps())] = 1.0 ./ A.S
    scale(A.Vt', Sinv) * A.U[:,1:n]'B
end

# Generalized svd
immutable GeneralizedSVD{T} <: Factorization{T}
    U::Matrix{T}
    V::Matrix{T}
    Q::Matrix{T}
    a::Vector
    b::Vector
    k::Int
    l::Int
    R::Matrix{T}
end

function svdfact!{T<:BlasFloat}(A::StridedMatrix{T}, B::StridedMatrix{T})
    U, V, Q, a, b, k, l, R = LAPACK.ggsvd!('U', 'V', 'Q', A, B)
    GeneralizedSVD(U, V, Q, a, b, int(k), int(l), R)
end
svdfact{T<:BlasFloat}(A::StridedMatrix{T}, B::StridedMatrix{T}) = svdfact!(copy(A),copy(B))
svdfact{TA,TB}(A::StridedMatrix{TA}, B::StridedMatrix{TB}) = (S = promote_type(Float32,typeof(one(TA)/norm(one(TA))),TB); svdfact!(S != TA ? convert(Matrix{S},A) : copy(A), S != TB ? convert(Matrix{S},B) : copy(B)))

function svd(A::AbstractMatrix, B::AbstractMatrix)
    F = svdfact(A, B)
    F[:U], F[:V], F[:Q]*F[:R0]', F[:D1], F[:D2]
end

function getindex{T}(obj::GeneralizedSVD{T}, d::Symbol)
    d == :U && return obj.U
    d == :V && return obj.V
    d == :Q && return obj.Q
    (d == :alpha || d == :a) && return obj.a
    (d == :beta || d == :b) && return obj.b
    (d == :vals || d == :S) && return obj.a[1:obj.k + obj.l] ./ obj.b[1:obj.k + obj.l]
    if d == :D1
        m = size(obj.U, 1)
        if m - obj.k - obj.l >= 0
            return [eye(T, obj.k) zeros(T, obj.k, obj.l); zeros(T, obj.l, obj.k) diagm(obj.a[obj.k + 1:obj.k + obj.l]); zeros(T, m - obj.k - obj.l, obj.k + obj.l)]
        else
            return [eye(T, m, obj.k) [zeros(T, obj.k, m - obj.k); diagm(obj.a[obj.k + 1:m])] zeros(T, m, obj.k + obj.l - m)]
        end
    end
    if d == :D2
        m = size(obj.U, 1)
        p = size(obj.V, 1)
        if m - obj.k - obj.l >= 0
            return [zeros(T, obj.l, obj.k) diagm(obj.b[obj.k + 1:obj.k + obj.l]); zeros(T, p - obj.l, obj.k + obj.l)]
        else
            return [zeros(T, p, obj.k) [diagm(obj.b[obj.k + 1:m]); zeros(T, obj.k + p - m, m - obj.k)] [zeros(T, m - obj.k, obj.k + obj.l - m); eye(T, obj.k + p - m, obj.k + obj.l - m)]]
        end
    end
    d == :R && return obj.R
    if d == :R0
        n = size(obj.Q, 1)
        return [zeros(T, obj.k + obj.l, n - obj.k - obj.l) obj.R]
    end
    throw(KeyError(d))
end

function svdvals!{T<:BlasFloat}(A::StridedMatrix{T}, B::StridedMatrix{T})
    _, _, _, a, b, k, l, _ = LAPACK.ggsvd!('N', 'N', 'N', A, B)
    a[1:k + l] ./ b[1:k + l]
end
svdvals{T<:BlasFloat}(A::StridedMatrix{T},B::StridedMatrix{T}) = svdvals!(copy(A),copy(B))
svdvals{TA,TB}(A::StridedMatrix{TA}, B::StridedMatrix{TB}) = (S = promote_type(Float32,typeof(one(T)/norm(one(TA))),TB); svdvals!(S != TA ? convert(Matrix{S}, A) : copy(A), S != TB ? convert(Matrix{S}, B) : copy(B)))

immutable Schur{Ty<:BlasFloat} <: Factorization{Ty}
    T::Matrix{Ty}
    Z::Matrix{Ty}
    values::Vector
end

schurfact!{T<:BlasFloat}(A::StridedMatrix{T}) = Schur(LinAlg.LAPACK.gees!('V', A)...)
schurfact{T<:BlasFloat}(A::StridedMatrix{T}) = schurfact!(copy(A))
schurfact{T}(A::StridedMatrix{T}) = (S = promote_type(Float32,typeof(one(T)/norm(one(T)))); S != T ? schurfact!(convert(Matrix{S},A)) : schurfact!(copy(A)))

function getindex(F::Schur, d::Symbol)
    (d == :T || d == :Schur) && return F.T
    (d == :Z || d == :vectors) && return F.Z
    d == :values && return F.values
    throw(KeyError(d))
end

function schur(A::AbstractMatrix)
    SchurF = schurfact(A)
    SchurF[:T], SchurF[:Z], SchurF[:values]
end

immutable GeneralizedSchur{Ty<:BlasFloat} <: Factorization{Ty}
    S::Matrix{Ty}
    T::Matrix{Ty}
    alpha::Vector
    beta::Vector{Ty}
    Q::Matrix{Ty}
    Z::Matrix{Ty}
end

schurfact!{T<:BlasFloat}(A::StridedMatrix{T}, B::StridedMatrix{T}) = GeneralizedSchur(LinAlg.LAPACK.gges!('V', 'V', A, B)...)
schurfact{T<:BlasFloat}(A::StridedMatrix{T},B::StridedMatrix{T}) = schurfact!(copy(A),copy(B))
schurfact{TA,TB}(A::StridedMatrix{TA}, B::StridedMatrix{TB}) = (S = promote_type(Float32,typeof(one(TA)/norm(one(TA))),TB); schurfact!(S != TA ? convert(Matrix{S},A) : copy(A), S != TB ? convert(Matrix{S},B) : copy(B)))

function getindex(F::GeneralizedSchur, d::Symbol)
    d == :S && return F.S
    d == :T && return F.T
    d == :alpha && return F.alpha
    d == :beta && return F.beta
    d == :values && return F.alpha./F.beta
    (d == :Q || d == :left) && return F.Q
    (d == :Z || d == :right) && return F.Z
    throw(KeyError(d))
end

function schur(A::AbstractMatrix, B::AbstractMatrix)
    SchurF = schurfact(A, B)
    SchurF[:S], SchurF[:T], SchurF[:Q], SchurF[:Z]
end

### General promotion rules
inv{T}(F::Factorization{T}) = A_ldiv_B!(F, eye(T, size(F,1)))
function \{TF<:Number,TB<:Number}(F::Factorization{TF}, B::AbstractVecOrMat{TB})
    TFB = typeof(one(TF)/one(TB)) 
    A_ldiv_B!(convert(typeof(F).name.primary{TFB}, F), TB == TFB ? copy(B) : convert(typeof(B).name.primary{TFB}, B))
end

function Ac_ldiv_B{TF<:Number,TB<:Number}(F::Factorization{TF}, B::AbstractVecOrMat{TB})
    TFB = typeof(one(TF)/one(TB)) 
    Ac_ldiv_B!(convert(typeof(F).name.primary{TFB}, F), TB == TFB ? copy(B) : convert(typeof(B).name.primary{TFB}, B))
end

function At_ldiv_B{TF<:Number,TB<:Number}(F::Factorization{TF}, B::AbstractVecOrMat{TB})
    TFB = typeof(one(TF)/one(TB)) 
    At_ldiv_B!(convert(typeof(F).name.primary{TFB}, F), TB == TFB ? copy(B) : convert(typeof(B).name.primary{TFB}, B))
end
