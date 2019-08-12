using SimpleClifford, Test, Random, Documenter

function stab_looks_good(s)
    c = canonicalize!(copy(s))
    phasesok = all((c.phases .== 0x0) .| (c.phases .== 0x2))
    H = stab_to_gf2(c)
    good_indices = reduce(|,H,dims=(1,))
    good_indices = good_indices[1:end÷2] .| good_indices[end÷2+1:end]
    rowsok = all(good_indices)
    good_indices = reduce(|,H,dims=(2,))
    colsok = all(good_indices)
    return phasesok && rowsok && colsok && check_allrowscommute(c)
end

function destab_looks_good(destabilizer)
    s = destabilizer.stabilizer
    d = destabilizer.destabilizer
    good = stab_looks_good(s)
    for i in eachindex(s)
        good &= comm(s[i],d[i])==0x1
        for j in eachindex(s)
            j==i && continue
            good &= comm(s[i],d[j])==0x0
        end
    end
    good
end

function mixed_destab_looks_good(destabilizer)
    s = destabilizer.stabilizer
    d = destabilizer.destabilizer
    x = destabilizer.logicalx
    z = destabilizer.logicalz
    good = check_allrowscommute(s)
    for i in eachindex(s)
        good &= comm(s[i],d[i])==0x1
        for j in eachindex(s)
            j==i && continue
            good &= comm(s[i],d[j])==0x0
        end
        for j in eachindex(x)
            good &= comm(s[i],x[j])==0x0
            good &= comm(s[i],z[j])==0x0
        end
    end
    for i in eachindex(x)
        for j in eachindex(x)
            good &= comm(x[i],x[j])==0x0
            good &= comm(z[i],z[j])==0x0
            if i==j
                good &= comm(x[i],z[j])==0x1
            else
                good &= comm(x[i],z[j])==0x0
            end
        end
    end
    good
end

test_sizes = [10,63,64,65,127,128,129] # Including sizes that would test off-by-one errors in the bit encoding.

function tests()

Random.seed!(42)

@testset "Doctests" begin
    DocMeta.setdocmeta!(SimpleClifford, :DocTestSetup, :(using SimpleClifford); recursive=true)
    doctest(SimpleClifford)
end

@testset "Pauli Operators" begin
    @testset "Parsing, constructors, and properties" begin
        @test P"-iXYZ" == PauliOperator(0x3, 3, vcat(BitArray([1,1,0]).chunks, BitArray([0,1,1]).chunks))
        @test P"-iXYZ" == PauliOperator(0x3, Bool[1,1,0], Bool[0,1,1])
        @test P"-iXYZ".xbit == Bool[1,1,0]
        @test P"-iXYZ".xz == UInt64[0x03, 0x06]
        @test P"-iXYZ".phase[] == 0x03 # TODO why is this failing?
        @test P"-iXYZ".nqubits == 3
        @test size(P"-iXYZ") == (3,)
    end
    @testset "Indexing" begin
        @test eachindex(P"IXYZ") == 1:4
        @test P"IXYZ"[3] == (true, true)
        p = P"IXYZ"
        @test p[[3,2]] == P"YX"
        p[4] = (true,false)
        @test p == P"IXYX"
    end
    @testset "Elementary operations" begin
        @test P"X"*P"Z" == P"-iY"
        @test comm(P"XX",P"YY") == 0x0
        @test comm(P"XZ",P"YZ") == 0x1
        @test prodphase(P"XX",P"YY") == 0x2
        @test prodphase(P"ZZZ",P"XXX") == 0x3
    end
    @testset "Commutation implies real phase" begin
        for i in 10
            for n in test_sizes
                p1,p2 = random_pauli(n; nophase=true), random_pauli(n; nophase=true)
                com = comm(p1,p2)==0x0
                p = prodphase(p1,p2)
                rea = p==0x0 || p==0x2
                @test (com && rea) || (!com && !rea)
            end
        end
    end
end

@testset "Pure and Mixed state initialization" begin
    @testset "Destabilizer initialization" begin
        for n in test_sizes
            @test destab_looks_good(Destabilizer(random_stabilizer(n)))
        end
    end
    @testset "Mixed destabilizer initialization" begin
        for n in test_sizes[2:end]
            @test mixed_destab_looks_good(MixedDestabilizer(random_stabilizer(rand(n÷2+1:n-4),n)))
        end
    end
end

@testset "Stabilizer canonicalization" begin
    @testset "Default canonicalization" begin
        s = S"- XZZZZ_____
              - _YZY___YX_
              - __XXZ__YX_
              + Z_Z_Y__YXZ
              + _____Z____
              + __________
              + __________
              + ______YYX_
              + __________
              + __________"
        canonicalize!(s)
        t = S"- XZZZZ_____
              - _YZY___YX_
              - __XXZ__YX_
              + Z_Z_Y__YXZ
              + ______YYX_
              + _____Z____
              + __________
              + __________
              + __________
              + __________"
        @test s == t
        for n in test_sizes
            @test stab_looks_good(random_stabilizer(n))
        end
    end
    @testset "Gottesman canonicalization" begin
        for n in test_sizes
            rs = random_stabilizer(rand(n÷3:n*2÷3),n)
            c = canonicalize!(copy(rs))
            g, _, _, perm1, perm2 = canonicalize_gott!(copy(rs))
            c = canonicalize!(colpermute!(colpermute!(copy(rs),perm1),perm2))
            cg = canonicalize!(copy(g))
            @test cg == c
            @test stab_looks_good(g)
        end
    end
end

@testset "Projective measurements" begin
    @testset "Stabilizer representation" begin
        s = S"XXX
              ZZI
              IZZ"
        ps, anticom, res = project!(copy(s), P"ZII")
        ps = canonicalize!(ps)
        @test anticom==1 && isnothing(res) && ps == S"ZII
                                                      IZI
                                                      IIZ"
        @test stab_looks_good(ps)

        ps, anticom, res = project!(copy(s), P"-XXX")
        @test anticom==0 && res[]==0x2 && ps == canonicalize!(copy(s))
        @test stab_looks_good(ps)

        ps, anticom, res = project!(copy(s), P"-XXX"; keep_result=false)
        @test anticom==0 && isnothing(res) && ps == s
        @test stab_looks_good(ps)

        for n in test_sizes
            s = random_stabilizer(n)
            m = random_pauli(n;nophase=true)
            ps, anticom, res = project!(copy(s),m)
            @test anticom==0x0 || ps[anticom]==m
            @test stab_looks_good(ps)
            m = single_z(n,1)
            ps, anticom, res = project!(copy(s),m)
            @test anticom==0x0 || ps[anticom]==m
            @test stab_looks_good(ps)
            m = single_x(n,1)
            ps, anticom, res = project!(copy(s),m)
            @test anticom==0x0 || ps[anticom]==m
            @test stab_looks_good(ps)
        end
    end
    @testset "Destabilizer representation" begin
        for n in test_sizes
            s = canonicalize!(random_stabilizer(n))
            m = random_pauli(n;nophase=true)
            ps, anticom, res = project!(copy(s),m)
            dps, danticom, dres = project!(Destabilizer(copy(s)),m)
            @test destab_looks_good(dps)
            @test anticom==danticom && res==dres && canonicalize!(ps)==canonicalize!(dps.stabilizer)
            m = single_z(n,1)
            ps, anticom, res = project!(copy(s),m)
            dps, danticom, dres = project!(Destabilizer(copy(s)),m)
            @test destab_looks_good(dps)
            @test anticom==danticom && res==dres && canonicalize!(ps)==canonicalize!(dps.stabilizer)
            m = single_x(n,1)
            ps, anticom, res = project!(copy(s),m)
            dps, danticom, dres = project!(Destabilizer(copy(s)),m)
            @test destab_looks_good(dps)
            @test anticom==danticom && res==dres && canonicalize!(ps)==canonicalize!(dps.stabilizer)
        end
    end
    @testset "Anticommutation indices and NA results" begin
        s = S" XXX
              -ZZI"
        ds = Destabilizer(copy(s))
        ms = MixedStabilizer(copy(s))
        mds = MixedDestabilizer(copy(s))

        p = P"IZZ"
        ps, a, r = project!(copy(s),p)
        @test stab_looks_good(ps)
        @test a==0 && isnothing(r)
        @test_throws BadDataStructure pds, a, r = project!(copy(ds),p)
        pms, a, r = project!(copy(ms),p)
        @test stab_looks_good(pms)
        @test pms.rank==3
        @test a==0 && isnothing(r)
        pmds, a, r = project!(copy(mds),p)
        @test mixed_destab_looks_good(pmds)
        @test pmds.rank==3
        @test a==0 && isnothing(r)

        p = P"ZZI"
        ps, a, r = project!(copy(s),p)
        @test stab_looks_good(ps)
        @test a==0 && r==0x2
        @test_throws BadDataStructure pds, a, r = project!(copy(ds),p)
        pms, a, r = project!(copy(ms),p)
        @test stab_looks_good(pms)
        @test pms.rank==2
        @test a==0 && r==0x2
        pmds, a, r = project!(copy(mds),p)
        @test mixed_destab_looks_good(pmds)
        @test pmds.rank==2
        @test a==0 && r==0x2
        @test canonicalize!(ps)==canonicalize!(pms.stabilizer)==canonicalize!(pmds.stabilizer)

        p = P"XZZ"
        ps, a, r = project!(copy(s),p)
        @test stab_looks_good(ps)
        @test a==2 && isnothing(r)
        pds, a, r = project!(copy(ds),p)
        @test destab_looks_good(pds)
        @test a==2 && isnothing(r)
        pms, a, r = project!(copy(ms),p)
        @test stab_looks_good(pms)
        @test pms.rank==2
        @test a==2 && isnothing(r)
        pmds, a, r = project!(copy(mds),p)
        @test mixed_destab_looks_good(pmds)
        @test pmds.rank==2
        @test a==2 && isnothing(r)
        @test canonicalize!(ps)==canonicalize!(pms.stabilizer)==canonicalize!(pds.stabilizer)==canonicalize!(pmds.stabilizer)
    end
    @testset "Mixed Destabilizer projection on logical operator" begin
        stab = one(MixedDestabilizer, 2,4)
        projzl = single_z(4,1)
        projzr = single_z(4,4)
        projxl = single_x(4,1)
        projxr = single_x(4,4)
        s, a, r = project!(copy(stab), projzl)
        @test mixed_destab_looks_good(s)
        @test a==0 && r==0x0       && s.stabilizer==S"Z___
                                                      _Z__"
        s, a, r = project!(copy(stab), projxl)
        @test mixed_destab_looks_good(s)
        @test a==1 && isnothing(r) && s.stabilizer==S"X___
                                                      _Z__"
        s, a, r = project!(copy(stab), projzr)
        @test mixed_destab_looks_good(s)
        @test a==0 && isnothing(r) && s.stabilizer==S"Z___
                                                      _Z__
                                                      ___Z"
        s, a, r = project!(copy(stab), projxr)
        @test mixed_destab_looks_good(s)
        @test a==0 && isnothing(r) && s.stabilizer==S"Z___
                                                      _Z__
                                                      ___X"
    end
end

@testset "GF(2) representations" begin
    @testset "Equivalence of GF(2) Gaussian elimination and Stabilizer canonicalization" begin
        for n in test_sizes
            for rep in 1:5
                s = random_stabilizer(n)[randperm(n)[1:rand(n÷2+1:n)]]
                cs = canonicalize!(copy(s));
                H = stab_to_gf2(cs);
                cH = gf2_gausselim!(stab_to_gf2(s));
                @test H==cH
            end
        end
    end
    @testset "GF(2) H and G matrices" begin
        for n in test_sizes
            for rep in 1:5
                H = random_invertible_gf2(n)[randperm(n)[1:rand(n÷2+1:n)],:]
                H = gf2_gausselim!(H)
                G = gf2_H_to_G(H)
                @test sum(G*H' .%2)==0;
            end
        end
    end
end

end

tests()
