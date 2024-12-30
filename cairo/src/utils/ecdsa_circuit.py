from random import randint

import garaga.hints.io as io
import garaga.modulo_circuit_structs as structs
from garaga.definitions import CURVES, CurveID, G1Point, G2Point
from garaga.hints import neg_3
from garaga.hints.ecip import (
    n_coeffs_from_n_points,
    n_points_from_n_coeffs,
    slope_intercept,
)
from garaga.modulo_circuit import WriteOps
from garaga.modulo_circuit_structs import G1PointCircuit, G2PointCircuit, u384
from garaga.precompiled_circuits.compilable_circuits.base import (
    BaseModuloCircuit,
    ModuloCircuit,
    PyFelt,
)
from garaga.precompiled_circuits.ec import (
    BasicEC,
    BasicECG2,
    ECIPCircuits,
    IsOnCurveCircuit,
)


class FullEcdsaCircuitBatched(BaseModuloCircuit):
    def __init__(
        self,
        curve_id: int,
        n_points: int = 2,
        auto_run: bool = True,
        compilation_mode: int = 0,
    ) -> None:
        self.n_points = n_points
        super().__init__(
            name=f"full_ecip_{n_points}P",
            curve_id=curve_id,
            auto_run=auto_run,
            compilation_mode=compilation_mode,
        )

    @staticmethod
    def _n_coeffs_from_n_points(n_points: int) -> tuple[int, int, int, int]:
        return (
            1 + n_points + 2,
            1 + n_points + 1 + 2,
            1 + n_points + 1 + 2,
            1 + n_points + 4 + 2,
        )

    @staticmethod
    def _n_points_from_n_coeffs(n_coeffs: int) -> int:
        # n_coeffs = 18 + 4n_points => 4n_points = n_coeffs - 18
        assert n_coeffs >= 18 + 4
        assert (n_coeffs - 18) % 4 == 0
        return (n_coeffs - 18) // 4

    def build_input(self) -> list[PyFelt]:
        input = []
        n_coeffs = self._n_coeffs_from_n_points(self.n_points)

        # RLCSumDlogDiv
        for _ in range(sum(n_coeffs)):
            input.append(self.field.random())

        for _ in range(self.n_points):
            input.append(self.field.random())  # x
            input.append(self.field.random())  # y
            input.append(self.field.random())  # ep_low
            input.append(self.field.random())  # en_low
            input.append(self.field.random())  # sp_low
            input.append(self.field.random())  # sn_low
            input.append(self.field.random())  # ep_high
            input.append(self.field.random())  # en_high
            input.append(self.field.random())  # sp_high
            input.append(self.field.random())  # sn_high

        # Q_low/high/high_shifted + A0
        for i in range(4):
            input.append(self.field.random())  # x
            input.append(self.field.random())  # y

        input.append(self.field(CURVES[self.curve_id].a))  # A_weirstrass
        input.append(self.field.random())  # base_rlc.

        return input

    def _run_circuit_inner(self, input: list[PyFelt]) -> ModuloCircuit:
        circuit = ECIPCircuits(
            self.name, self.curve_id, compilation_mode=self.compilation_mode
        )
        n_coeffs = self._n_coeffs_from_n_points(self.n_points)
        ff_coeffs = input[: sum(n_coeffs)]

        all_points = input[sum(n_coeffs) :]

        def split_list(input_list, lengths):
            start_idx, result = 0, []
            for length in lengths:
                result.append(input_list[start_idx : start_idx + length])
                start_idx += length
            return result

        points = []
        ep_lows = []
        en_lows = []
        sp_lows = []
        sn_lows = []
        ep_highs = []
        en_highs = []
        sp_highs = []
        sn_highs = []
        for i in range(self.n_points):
            points.append(
                circuit.write_struct(
                    G1PointCircuit(f"p_{i}", all_points[i * 8 : i * 8 + 2]),
                )
            )
            ep_lows.append(all_points[i * 8 + 3])
            en_lows.append(all_points[i * 8 + 4])
            sp_lows.append(all_points[i * 8 + 5])
            sn_lows.append(all_points[i * 8 + 6])
            ep_highs.append(all_points[i * 8 + 7])
            en_highs.append(all_points[i * 8 + 8])
            sp_highs.append(all_points[i * 8 + 9])
            sn_highs.append(all_points[i * 8 + 10])

        epns_low = circuit.write_struct(
            structs.StructSpan(
                "epns_low",
                [
                    structs.Tuple(
                        f"epn_{i}",
                        elmts=[
                            structs.u384("ep", [ep_lows[i]]),
                            structs.u384("en", [en_lows[i]]),
                            structs.u384("sp", [sp_lows[i]]),
                            structs.u384("sn", [sn_lows[i]]),
                        ],
                    )
                    for i in range(self.n_points)
                ],
            )
        )

        print(f"epns_low: {epns_low} (n_points: {self.n_points})")

        epns_high = circuit.write_struct(
            structs.StructSpan(
                "epns_high",
                [
                    structs.Tuple(
                        f"epn_{i}",
                        elmts=[
                            structs.u384("ep", [ep_highs[i]]),
                            structs.u384("en", [en_highs[i]]),
                            structs.u384("sp", [sp_highs[i]]),
                            structs.u384("sn", [sn_highs[i]]),
                        ],
                    )
                    for i in range(self.n_points)
                ],
            )
        )

        rest_points = all_points[self.n_points * 8 :]
        q_low = circuit.write_struct(
            structs.G1PointCircuit("q_low", elmts=rest_points[0:2])
        )
        q_high = circuit.write_struct(
            structs.G1PointCircuit("q_high", elmts=rest_points[2:4])
        )

        q_high_shifted = circuit.write_struct(
            structs.G1PointCircuit("q_high_shifted", elmts=rest_points[4:6]),
        )
        a0 = circuit.write_struct(structs.G1PointCircuit("a0", elmts=rest_points[6:8]))

        A_weirstrass = circuit.write_struct(
            structs.u384("A_weirstrass", elmts=[rest_points[8]])
        )
        base_rlc = circuit.write_struct(
            structs.u384("base_rlc", elmts=[rest_points[9]])
        )

        m_A0, b_A0, xA0, yA0, xA2, yA2, coeff0, coeff2 = (
            circuit._slope_intercept_same_point(a0, A_weirstrass)
        )

        def get_log_div_coeffs(circuit, ff_coeffs):
            _log_div_a_num, _log_div_a_den, _log_div_b_num, _log_div_b_den = split_list(
                ff_coeffs, self._n_coeffs_from_n_points(self.n_points)
            )
            log_div_a_num, log_div_a_den, log_div_b_num, log_div_b_den = (
                circuit.write_struct(
                    structs.FunctionFeltCircuit(
                        name="SumDlogDiv",
                        elmts=[
                            structs.u384Span("log_div_a_num", _log_div_a_num),
                            structs.u384Span("log_div_a_den", _log_div_a_den),
                            structs.u384Span("log_dsumiv_b_num", _log_div_b_num),
                            structs.u384Span("log_div_b_den", _log_div_b_den),
                        ],
                    ),
                    WriteOps.INPUT,
                )
            )

            return log_div_a_num, log_div_a_den, log_div_b_num, log_div_b_den

        log_div_a_num_low, log_div_a_den_low, log_div_b_num_low, log_div_b_den_low = (
            get_log_div_coeffs(circuit, ff_coeffs)
        )

        lhs = circuit._eval_function_challenge_dupl(
            (xA0, yA0),
            (xA2, yA2),
            coeff0,
            coeff2,
            log_div_a_num_low,
            log_div_a_den_low,
            log_div_b_num_low,
            log_div_b_den_low,
        )

        def compute_base_rhs(circuit: ECIPCircuits, points, epns, m_A0, b_A0, xA0):
            acc = circuit.set_or_get_constant(0)
            for pt, _epns in zip(points, epns):
                _epns = io.flatten(_epns)
                acc = circuit._accumulate_eval_point_challenge_signed_same_point(
                    eval_accumulator=acc,
                    slope_intercept=(m_A0, b_A0),
                    xA=xA0,
                    P=pt,
                    ep=_epns[0],
                    en=_epns[1],
                    sign_ep=_epns[2],
                    sign_en=_epns[3],
                )
            return acc

        base_rhs_low = compute_base_rhs(circuit, points, epns_low, m_A0, b_A0, xA0)
        rhs_low = circuit._RHS_finalize_acc(
            base_rhs_low, (m_A0, b_A0), xA0, (q_low[0], q_low[1])
        )

        base_rhs_high = compute_base_rhs(circuit, points, epns_high, m_A0, b_A0, xA0)
        rhs_high = circuit._RHS_finalize_acc(
            base_rhs_high, (m_A0, b_A0), xA0, (q_high[0], q_high[1])
        )

        base_rhs_high_shifted = (
            circuit._compute_eval_point_challenge_signed_same_point_2_pow_128(
                (m_A0, b_A0),
                xA0,
                q_high,
            )
        )
        rhs_high_shifted = circuit._RHS_finalize_acc(
            base_rhs_high_shifted,
            (m_A0, b_A0),
            xA0,
            (q_high_shifted[0], q_high_shifted[1]),
        )

        c0 = base_rlc
        c1 = circuit.mul(c0, c0, "c1 = c0^2")
        c2 = circuit.mul(c1, c0, "c2 = c0^3")

        rhs = circuit.sum(
            [
                circuit.mul(rhs_low, c0, "rhs_low * c0"),
                circuit.mul(rhs_high, c1, "rhs_high * c1"),
                circuit.mul(rhs_high_shifted, c2, "rhs_high_shifted * c2"),
            ],
            "Sum of rhs_low * c0, rhs_high * c1, rhs_high_shifted * c2",
        )

        final_check = circuit.sub_and_assert(
            lhs, rhs, circuit.set_or_get_constant(0), "Assert lhs - rhs = 0"
        )

        # Compute Q_low + Q_high_shifted.

        circuit.extend_struct_output(u384("final_check", [final_check]))

        return circuit


if __name__ == "__main__":
    circuit = FullEcdsaCircuitBatched(CurveID.SECP256K1.value, n_points=2)
    code, _ = circuit.circuit.compile_circuit()
    print(code)
