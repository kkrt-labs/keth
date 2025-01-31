@known_ap_change
func is_zero(value) -> felt {
    if (value == 0) {
        return 1;
    }

    return 0;
}

@known_ap_change
func is_not_zero(value) -> felt {
    if (value != 0) {
        return 1;
    }

    return 0;
}
