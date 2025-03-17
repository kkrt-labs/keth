// from cairo_ec.curve.g1g2pair import G1G2Pair

struct Point {
    x: felt,
    y: felt,
}

struct ReturnPoint {
    p1: Point,
    p2: felt,
}

func return_tuple_same_struct_params(pt: Point, q: Point) -> (Point, felt, ReturnPoint) {
    tempvar l = (q.y - pt.y) / (q.x - pt.x);

    tempvar x = l * l - pt.x - q.x;
    tempvar y = l * (pt.x - x) - pt.y;

    let res = Point(x, y);
    let res2 = ReturnPoint(res, x);
    return (res, 2, res2);

    end:
}

func return_single_same_struct_params(pt: Point, q: Point) -> Point {
    tempvar l = (q.y - pt.y) / (q.x - pt.x);

    tempvar x = l * l - pt.x - q.x;
    tempvar y = l * (pt.x - x) - pt.y;

    let res = Point(x, y);
    return res;

    end:
}

func return_single_nested_struct_params(pt: Point, q: Point) -> ReturnPoint {
    tempvar l = (q.y - pt.y) / (q.x - pt.x);

    tempvar x = l * l - pt.x - q.x;
    tempvar y = l * (pt.x - x) - pt.y;

    let res = Point(x, y);
    let res2 = ReturnPoint(res, x);
    return res2;

    end:
}

func ec_add_struct(pt: Point, q: Point) -> Point {
    tempvar l = (q.y - pt.y) / (q.x - pt.x);

    tempvar x = l * l - pt.x - q.x;
    tempvar y = l * (pt.x - x) - pt.y;

    let res = Point(x, y);
    return res;

    end:
}
