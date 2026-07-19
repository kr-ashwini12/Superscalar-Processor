
create_clock -name clk -period 20.000 [get_ports clk_i]

# reset_i is asynchronous and not a timing-critical path — exclude it from
# setup/hold analysis so it doesn't get treated as a second clock domain.
set_false_path -from [get_ports reset_i]

derive_clock_uncertainty
