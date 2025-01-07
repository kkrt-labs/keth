import pytest

pytestmark = pytest.mark.python_vm


@pytest.mark.parametrize(
    "test_case",
    ["test__dict_copy__should_return_copied_dict"],
)
def test_dict(cairo_run, test_case):
    cairo_run(test_case)
