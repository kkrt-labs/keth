import pytest


class TestArray:
    class TestReverse:
        @pytest.mark.parametrize(
            "arr",
            [
                [0, 1, 2, 3, 4],
                [0, 1, 2, 3],
                [0, 1, 2],
                [0, 1],
                [0],
                [],
            ],
        )
        def test_should_return_reversed_array(self, cairo_run, arr):
            output = cairo_run("test__reverse", data=bytes(arr))
            assert arr[::-1] == (output if isinstance(output, list) else [output])

    class TestCountNotZero:
        @pytest.mark.parametrize(
            "arr",
            [
                [0, 1, 0, 0, 4],
                [0, 1, 0, 3],
                [0, 1, 0],
                [0, 1],
                [0],
                [],
            ],
        )
        def test_should_return_count_of_non_zero_elements(self, cairo_run, arr):
            output = cairo_run("test__count_not_zero", data=bytes(arr))
            assert len(arr) - arr.count(0) == output
