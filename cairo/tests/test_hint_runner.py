import pytest
from ethereum_types.numeric import U256


class TestRunner:
    def test__ap_accessible(self, cairo_run, cairo_run_py):
        cairo_run("test__ap_accessible")
        cairo_run_py("test__ap_accessible")

    def test__pc_accessible(self, cairo_run, cairo_run_py):
        cairo_run("test__pc_accessible")
        cairo_run_py("test__pc_accessible")

    def test__fp_accessible(self, cairo_run, cairo_run_py):
        cairo_run("test__fp_accessible")
        cairo_run_py("test__fp_accessible")

    def test__should_assign_tempvar_ids_variable(self, cairo_run, cairo_run_py):
        cairo_run("test__assign_tempvar_ids_variable")
        cairo_run_py("test__assign_tempvar_ids_variable")

    def test__should_assign_local_unassigned_variable(self, cairo_run, cairo_run_py):
        cairo_run("test__assign_local_unassigned_variable")
        cairo_run_py("test__assign_local_unassigned_variable")

    def test__should_fail_assign_already_assigned_variable_should_fail(
        self, cairo_run, cairo_run_py
    ):
        with pytest.raises(Exception):
            cairo_run("test__assign_already_assigned_variable_should_fail")
        with pytest.raises(Exception):
            cairo_run_py("test__assign_already_assigned_variable_should_fail")

    def test__assign_memory(self, cairo_run, cairo_run_py):
        cairo_run("test__assign_memory")
        cairo_run_py("test__assign_memory")

    def test__access_struct_members(self, cairo_run, cairo_run_py):
        cairo_run("test__access_struct_members")
        cairo_run_py("test__access_struct_members")

    def test__access_struct_members_pointers(self, cairo_run, cairo_run_py):
        cairo_run("test__access_struct_members_pointers")
        cairo_run_py("test__access_struct_members_pointers")

    def test_access_nested_structs(self, cairo_run, cairo_run_py):
        cairo_run("test_access_nested_structs")
        cairo_run_py("test_access_nested_structs")

    def test_access_struct_member_address(self, cairo_run, cairo_run_py):
        cairo_run("test_access_struct_member_address")
        cairo_run_py("test_access_struct_member_address")

    def test__serialize(self, cairo_run, cairo_run_py):
        cairo_run("test__serialize", n=U256(100))
        cairo_run_py("test__serialize", n=U256(100))

    def test__gen_arg_pointer(self, cairo_run, cairo_run_py):
        cairo_run("test__gen_arg_pointer", n=U256(100))
        cairo_run_py("test__gen_arg_pointer", n=U256(100))

    def test__gen_arg_struct(self, cairo_run):
        cairo_run("test__gen_arg_struct", n=U256(100))
        # Not possible with the Python runner but is a nice addition to the Rust one.

    def test__access_let_felt(self, cairo_run, cairo_run_py):
        cairo_run("test__access_let_felt")
        cairo_run_py("test__access_let_felt")

    def test__access_let_relocatable(self, cairo_run, cairo_run_py):
        cairo_run("test__access_let_relocatable")
        cairo_run_py("test__access_let_relocatable")
