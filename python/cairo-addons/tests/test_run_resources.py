from cairo_addons.vm import RunResources


class TestRunResources:
    def test_init_default(self):
        run_resources = RunResources()
        assert run_resources.n_steps is None

    def test_init_with_n_steps(self):
        run_resources = RunResources(n_steps=100)
        assert run_resources.n_steps == 100
