###########################################################################
#
#  SerialMC runner: consumes repeatedly a sampler and returns a MCMCChain
#
#
###########################################################################

export SerialMC

println("Loading SerialMC(burnin, thinning, len, r) runner")

immutable SerialMC <: MCMCRunner
  burnin::Integer
  thinning::Integer
  len::Integer
  r::Range

  function SerialMC(steps::Range{Int})
    r = steps

    burnin = first(r)-1
    thinning = r.step
    len = last(r)

    assert(burnin >= 0, "Burnin rounds ($burnin) should be >= 0")
    assert(len > burnin, "Total MCMC length ($len) should be > to burnin ($burnin)")  
    assert(thinning >= 1, "Thinning ($thinning) should be >= 1") 

    new(burnin, thinning, len, r)
  end
end

SerialMC(steps::Range1{Int}) = SerialMC(first(steps):1:last(steps))

SerialMC(; steps::Integer=100, burnin::Integer=0, thinning::Integer=1) = SerialMC((burnin+1):thinning:steps)

function run_serialmc(t::MCMCTask)
  tic() # start timer

  # temporary array to store samples
  samples = fill(NaN, t.model.size, length(t.runner.r))
  gradients = fill(NaN, t.model.size, length(t.runner.r))
  diags = DataFrame(step=collect(t.runner.r)) # initialize with column 'step'

  # sampling loop
  j = 1
  for i in 1:t.runner.len
    newprop = consume(t.task)
    if in(i, t.runner.r)
      samples[:, j] = newprop.ppars
      if newprop.pgrads != nothing
        gradients[:, j] = newprop.pgrads
      end

      # save diagnostics
      for (k,v) in newprop.diagnostics
        # if diag name not seen before, create column
        if !in(k, colnames(diags))
          diags[string(k)] = DataArray(Array(typeof(v), nrow(diags)), falses(nrow(diags)) )
        end
        
        diags[j, string(k)] = v
      end

      j += 1
    end
  end

  # generate column names for the samples DataFrame
  cn = ASCIIString[]
  for (k,v) in t.model.pmap
      if length(v.dims) == 0 # scalar
        push!(cn, string(k))
      elseif length(v.dims) == 1 # vector
        cn = vcat(cn, ASCIIString[ "$k.$i" for i in 1:v.dims[1] ])
      elseif length(v.dims) == 2 # matrix
        cn = vcat(cn, ASCIIString[ "$k.$i.$j" for i in 1:v.dims[1], j in 1:v.dims[2] ])
      end
  end

  # create Chain
  MCMCChain(t.runner.r, DataFrame(samples', cn), DataFrame(gradients', cn), diags, t, toq())
end

function resume_serialmc(t::MCMCTask; steps::Integer=100)
  assert(typeof(t.runner) == SerialMC,
    "resume_serialmc can not be called on an MCMCTask whose runner is of type $(fieldtype(t, :runner))")
  run(t.model, t.sampler, SerialMC(steps=steps, thinning=t.runner.thinning))
end