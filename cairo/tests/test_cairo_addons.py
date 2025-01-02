from cairo_addons.vm import hello_from_bin


def test_hello_from_bin():
    assert hello_from_bin() == "Hello from cairo-addons 1000!"
