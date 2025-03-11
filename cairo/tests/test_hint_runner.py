import pytest
from ethereum_types.numeric import U256


class TestRunner:
    def test__ap_accessible(self, cairo_run):
        cairo_run("test__ap_accessible")

    def test__pc_accessible(self, cairo_run):
        cairo_run("test__pc_accessible")

    def test__fp_accessible(self, cairo_run):
        cairo_run("test__fp_accessible")

    def test__should_assign_tempvar_ids_variable(self, cairo_run):
        cairo_run("test__assign_tempvar_ids_variable")

    def test__should_assign_local_unassigned_variable(self, cairo_run):
        cairo_run("test__assign_local_unassigned_variable")

    def test__should_fail_assign_already_assigned_variable(self, cairo_run):
        with pytest.raises(Exception):
            cairo_run("test__assign_already_assigned_variable")

    def test__assign_memory(self, cairo_run):
        cairo_run("test__assign_memory")

    def test__serialize(self, cairo_run):
        cairo_run("test__serialize", n=U256(100))
