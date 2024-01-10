BUILD_DIR?=obj_dir
ROOT_DIR=$(patsubst %/tb/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
SRC_DIR=$(ROOT_DIR)/src
TB_DIR=$(ROOT_DIR)/tb
DEPS_DIR=$(ROOT_DIR)/deps
INC_DIR=$(ROOT_DIR)/include  $(DEPS_DIR)/common_cells/src
SRC=$(shell find $(SRC_DIR) -name "*.sv")
TB_SRC=$(TB_DIR)/verilator_test_top.sv
CPP_SRC=$(TB_DIR)/verilator_test_top.cpp

# TODO: a better IP management method
COMMON_CELL_DIR=$(DEPS_DIR)/common_cells/src
TECH_CELL_DIR=$(DEPS_DIR)/tech_cells_generic/src/rtl
DEPS_SRC=$(COMMON_CELL_DIR)/cf_math_pkg.sv \
         $(COMMON_CELL_DIR)/fifo_v3.sv \
         $(COMMON_CELL_DIR)/fall_through_register.sv \
				 $(COMMON_CELL_DIR)/lzc.sv \
			   $(COMMON_CELL_DIR)/rr_arb_tree.sv \
			   $(TECH_CELL_DIR)/tc_sram.sv

Verilator_inc_args = $(addprefix -I,$(INC_DIR))

test_top:
	verilator -Wall -Wno-fatal --cc --exe --Mdir $(BUILD_DIR) \
	--top verilator_test_top $(Verilator_inc_args) \
	$(if $(trace),--trace --trace-structs --trace-fst) \
	$(if $(DUMP_VRF_ACCESS), -DDUMP_VRF_ACCESS) \
	$(DEPS_SRC) $(SRC) $(TB_SRC) $(CPP_SRC) 2>&1 | tee log.txt
	make -C $(BUILD_DIR) -f Vverilator_test_top.mk -j8

rvv_core:
	verilator -Wall -Wno-fatal --cc --Mdir $(BUILD_DIR) \
	--top rvv_core -CFLAGS "-fpic -std=c++17" $(Verilator_inc_args) \
	$(if $(trace),--trace --trace-structs --trace-fst) \
	$(if $(DUMP_VRF_ACCESS), -DDUMP_VRF_ACCESS) \
	$(DEPS_SRC) $(SRC)

clean:
	rm -rf $(BUILD_DIR)
