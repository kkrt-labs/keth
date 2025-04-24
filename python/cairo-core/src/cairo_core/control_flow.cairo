// @dev Raise by asserting [ap - 1] == [ap - 2];
//      The instruction is dw to have the last instruction run failing,
//      while using assert [ap - 1] = [ap - 2] would require to add ret;
//      at the end of the function, which would then not be covered.
func raise(message: felt) {
    with_attr error_message("{message}") {
        raise_label:
        [ap] = 0, ap++;
        [ap] = 1, ap++;
        dw 0x40127ffe7fff7fff;
    }
}

func raise_ValueError(message: felt) {
    with_attr error_message("ValueError: {message}") {
        raise_label:
        [ap] = 0, ap++;
        [ap] = 1, ap++;
        dw 0x40127ffe7fff7fff;
    }
}
