set_property IOSTANDARD LVCMOS33 [get_ports resetn_in]
set_property PACKAGE_PIN U18 [get_ports resetn_in]
set_property PACKAGE_PIN W5 [get_ports clk_in]

create_clock -name clk100 -period 10.000 [get_ports clk_in]


set_property IOSTANDARD LVCMOS33 [get_ports clk_in]
set_property IOSTANDARD LVCMOS33 [get_ports i2s_rx_lrclk]
set_property IOSTANDARD LVCMOS33 [get_ports i2s_rx_sclk]
set_property IOSTANDARD LVCMOS33 [get_ports i2s_rx_sdata]
set_property IOSTANDARD LVCMOS33 [get_ports i2s_tx_lrclk]
set_property IOSTANDARD LVCMOS33 [get_ports i2s_tx_sclk]
set_property IOSTANDARD LVCMOS33 [get_ports i2s_tx_sdata]

set_property PACKAGE_PIN H2 [get_ports i2s_rx_sclk]
set_property PACKAGE_PIN G3 [get_ports i2s_rx_sdata]
set_property PACKAGE_PIN L2 [get_ports i2s_tx_lrclk]
set_property PACKAGE_PIN J2 [get_ports i2s_tx_sclk]
set_property PACKAGE_PIN G2 [get_ports i2s_tx_sdata]

set_property IOSTANDARD LVCMOS33 [get_ports i2s_rx_mclk]
set_property IOSTANDARD LVCMOS33 [get_ports i2s_tx_mclk]
set_property PACKAGE_PIN J1 [get_ports i2s_tx_mclk]
set_property PACKAGE_PIN H1 [get_ports i2s_rx_mclk]
set_property PACKAGE_PIN K2 [get_ports i2s_rx_lrclk]
