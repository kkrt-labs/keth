from starkware.cairo.common.registers import get_fp_and_pc, get_label_location

func get_ADD_EC_POINT_circuit() -> (add_offsets: felt*, mul_offsets: felt*) {
    alloc_locals;
    // let (__fp__, _) = get_fp_and_pc();
    // let (constants_ptr: felt*) = get_label_location(constants_ptr_loc);
    let (add_offsets_ptr: felt*) = get_label_location(add_offsets_ptr_loc);
    let (mul_offsets_ptr: felt*) = get_label_location(mul_offsets_ptr_loc);
    // let (output_offsets_ptr: felt*) = get_label_location(output_offsets_ptr_loc);
    // let constants_ptr_len = 0;
    // let input_len = 16;
    // let witnesses_len = 0;
    // let output_len = 8;
    // let continuous_output = 0;
    // let add_mod_n = 6;
    // let mul_mod_n = 3;
    // let n_assert_eq = 0;
    // let name = 'add_ec_point';
    // let curve_id = curve_id;
    // local circuit: ModuloCircuit = ModuloCircuit(
    //     constants_ptr,
    //     add_offsets_ptr,
    //     mul_offsets_ptr,
    //     output_offsets_ptr,
    //     constants_ptr_len,
    //     input_len,
    //     witnesses_len,
    //     output_len,
    //     continuous_output,
    //     add_mod_n,
    //     mul_mod_n,
    //     n_assert_eq,
    //     name,
    //     curve_id,
    // );
    // return (&circuit,);

    // constants_ptr_loc:

    return (add_offsets_ptr, mul_offsets_ptr);

    add_offsets_ptr_loc:
    dw 12;  // None
    dw 16;
    dw 4;
    dw 8;  // None
    dw 20;
    dw 0;
    dw 0;  // None
    dw 32;
    dw 28;
    dw 8;  // None
    dw 36;
    dw 32;
    dw 36;  // None
    dw 40;
    dw 0;
    dw 4;  // None
    dw 48;
    dw 44;

    mul_offsets_ptr_loc:
    dw 20;  // None
    dw 24;
    dw 16;
    dw 24;  // None
    dw 24;
    dw 28;
    dw 24;  // None
    dw 40;
    dw 44;

    output_offsets_ptr_loc:
    dw 36;
    dw 48;
}

func get_DOUBLE_EC_POINT_circuit() -> (add_offsets: felt*, mul_offsets: felt*) {
    // alloc_locals;
    // let (__fp__, _) = get_fp_and_pc();
    // let (constants_ptr: felt*) = get_label_location(constants_ptr_loc);
    let (add_offsets_ptr: felt*) = get_label_location(add_offsets_ptr_loc);
    let (mul_offsets_ptr: felt*) = get_label_location(mul_offsets_ptr_loc);
    // let (output_offsets_ptr: felt*) = get_label_location(output_offsets_ptr_loc);
    // let constants_ptr_len = 1;
    // let input_len = 12;
    // let witnesses_len = 0;
    // let output_len = 8;
    // let continuous_output = 0;
    // let add_mod_n = 6;
    // let mul_mod_n = 5;
    // let n_assert_eq = 0;
    // let name = 'double_ec_point';
    // let curve_id = curve_id;
    // local circuit: ModuloCircuit = ModuloCircuit(
    //     constants_ptr,
    //     add_offsets_ptr,
    //     mul_offsets_ptr,
    //     output_offsets_ptr,
    //     constants_ptr_len,
    //     input_len,
    //     witnesses_len,
    //     output_len,
    //     continuous_output,
    //     add_mod_n,
    //     mul_mod_n,
    //     n_assert_eq,
    //     name,
    //     curve_id,
    // );
    // return (&circuit,);

    // constants_ptr_loc:
    // dw 3;
    // dw 0;
    // dw 0;
    // dw 0;

    return (add_offsets_ptr, mul_offsets_ptr);

    add_offsets_ptr_loc:
    dw 20;  // None
    dw 12;
    dw 24;
    dw 8;  // None
    dw 8;
    dw 28;
    dw 4;  // None
    dw 40;
    dw 36;
    dw 4;  // None
    dw 44;
    dw 40;
    dw 44;  // None
    dw 48;
    dw 4;
    dw 8;  // None
    dw 56;
    dw 52;

    mul_offsets_ptr_loc:
    dw 4;  // None
    dw 4;
    dw 16;
    dw 0;  // None
    dw 16;
    dw 20;
    dw 28;  // None
    dw 32;
    dw 24;
    dw 32;  // None
    dw 32;
    dw 36;
    dw 32;  // None
    dw 48;
    dw 52;

    output_offsets_ptr_loc:
    dw 44;
    dw 56;
}

func get_full_ecip_2P_circuit() -> (add_offsets: felt*, mul_offsets: felt*) {
    // alloc_locals;
    // let (__fp__, _) = get_fp_and_pc();
    // let (constants_ptr: felt*) = get_label_location(constants_ptr_loc);
    let (add_offsets_ptr: felt*) = get_label_location(add_offsets_ptr_loc);
    let (mul_offsets_ptr: felt*) = get_label_location(mul_offsets_ptr_loc);
    // let (output_offsets_ptr: felt*) = get_label_location(output_offsets_ptr_loc);
    // let constants_ptr_len = 4;
    // let input_len = 224;
    // let witnesses_len = 0;
    // let output_len = 4;
    // let continuous_output = 1;
    // let add_mod_n = 117;
    // let mul_mod_n = 108;
    // let n_assert_eq = 1;
    // let name = 'full_ecip_2P';
    // let curve_id = curve_id;
    // local circuit: ModuloCircuit = ModuloCircuit(
    //     constants_ptr,
    //     add_offsets_ptr,
    //     mul_offsets_ptr,
    //     output_offsets_ptr,
    //     constants_ptr_len,
    //     input_len,
    //     witnesses_len,
    //     output_len,
    //     continuous_output,
    //     add_mod_n,
    //     mul_mod_n,
    //     n_assert_eq,
    //     name,
    //     curve_id,
    // );
    // return (&circuit,);

    // constants_ptr_loc:
    // dw 3;
    // dw 0;
    // dw 0;
    // dw 0;
    // dw 0;
    // dw 0;
    // dw 0;
    // dw 0;
    // dw 12528508628158887531275213211;
    // dw 66632300;
    // dw 0;
    // dw 0;
    // dw 12528508628158887531275213211;
    // dw 4361599596;
    // dw 0;
    // dw 0;
    return (add_offsets_ptr, mul_offsets_ptr);

    add_offsets_ptr_loc:
    dw 244;  // None
    dw 232;
    dw 248;
    dw 228;  // None
    dw 228;
    dw 252;
    dw 260;  // None
    dw 264;
    dw 228;
    dw 224;  // None
    dw 224;
    dw 272;
    dw 272;  // None
    dw 276;
    dw 268;
    dw 276;  // None
    dw 280;
    dw 224;
    dw 228;  // None
    dw 288;
    dw 284;
    dw 288;  // None
    dw 292;
    dw 4;
    dw 228;  // None
    dw 296;
    dw 292;
    dw 224;  // None
    dw 300;
    dw 276;
    dw 292;  // None
    dw 292;
    dw 312;
    dw 276;  // None
    dw 316;
    dw 224;
    dw 308;  // None
    dw 308;
    dw 332;
    dw 332;  // None
    dw 336;
    dw 232;
    dw 328;  // None
    dw 336;
    dw 340;
    dw 304;  // None
    dw 304;
    dw 348;
    dw 344;  // None
    dw 348;
    dw 352;
    dw 28;  // Eval sumdlogdiv_a_num Horner step: add coefficient_3
    dw 356;
    dw 360;
    dw 24;  // Eval sumdlogdiv_a_num Horner step: add coefficient_2
    dw 364;
    dw 368;
    dw 20;  // Eval sumdlogdiv_a_num Horner step: add coefficient_1
    dw 372;
    dw 376;
    dw 16;  // Eval sumdlogdiv_a_num Horner step: add coefficient_0
    dw 380;
    dw 384;
    dw 52;  // Eval sumdlogdiv_a_den Horner step: add coefficient_4
    dw 388;
    dw 392;
    dw 48;  // Eval sumdlogdiv_a_den Horner step: add coefficient_3
    dw 396;
    dw 400;
    dw 44;  // Eval sumdlogdiv_a_den Horner step: add coefficient_2
    dw 404;
    dw 408;
    dw 40;  // Eval sumdlogdiv_a_den Horner step: add coefficient_1
    dw 412;
    dw 416;
    dw 36;  // Eval sumdlogdiv_a_den Horner step: add coefficient_0
    dw 420;
    dw 424;
    dw 76;  // Eval sumdlogdiv_b_num Horner step: add coefficient_4
    dw 432;
    dw 436;
    dw 72;  // Eval sumdlogdiv_b_num Horner step: add coefficient_3
    dw 440;
    dw 444;
    dw 68;  // Eval sumdlogdiv_b_num Horner step: add coefficient_2
    dw 448;
    dw 452;
    dw 64;  // Eval sumdlogdiv_b_num Horner step: add coefficient_1
    dw 456;
    dw 460;
    dw 60;  // Eval sumdlogdiv_b_num Horner step: add coefficient_0
    dw 464;
    dw 468;
    dw 112;  // Eval sumdlogdiv_b_den Horner step: add coefficient_7
    dw 472;
    dw 476;
    dw 108;  // Eval sumdlogdiv_b_den Horner step: add coefficient_6
    dw 480;
    dw 484;
    dw 104;  // Eval sumdlogdiv_b_den Horner step: add coefficient_5
    dw 488;
    dw 492;
    dw 100;  // Eval sumdlogdiv_b_den Horner step: add coefficient_4
    dw 496;
    dw 500;
    dw 96;  // Eval sumdlogdiv_b_den Horner step: add coefficient_3
    dw 504;
    dw 508;
    dw 92;  // Eval sumdlogdiv_b_den Horner step: add coefficient_2
    dw 512;
    dw 516;
    dw 88;  // Eval sumdlogdiv_b_den Horner step: add coefficient_1
    dw 520;
    dw 524;
    dw 84;  // Eval sumdlogdiv_b_den Horner step: add coefficient_0
    dw 528;
    dw 532;
    dw 428;  // None
    dw 540;
    dw 544;
    dw 28;  // Eval sumdlogdiv_a_num Horner step: add coefficient_3
    dw 548;
    dw 552;
    dw 24;  // Eval sumdlogdiv_a_num Horner step: add coefficient_2
    dw 556;
    dw 560;
    dw 20;  // Eval sumdlogdiv_a_num Horner step: add coefficient_1
    dw 564;
    dw 568;
    dw 16;  // Eval sumdlogdiv_a_num Horner step: add coefficient_0
    dw 572;
    dw 576;
    dw 52;  // Eval sumdlogdiv_a_den Horner step: add coefficient_4
    dw 580;
    dw 584;
    dw 48;  // Eval sumdlogdiv_a_den Horner step: add coefficient_3
    dw 588;
    dw 592;
    dw 44;  // Eval sumdlogdiv_a_den Horner step: add coefficient_2
    dw 596;
    dw 600;
    dw 40;  // Eval sumdlogdiv_a_den Horner step: add coefficient_1
    dw 604;
    dw 608;
    dw 36;  // Eval sumdlogdiv_a_den Horner step: add coefficient_0
    dw 612;
    dw 616;
    dw 76;  // Eval sumdlogdiv_b_num Horner step: add coefficient_4
    dw 624;
    dw 628;
    dw 72;  // Eval sumdlogdiv_b_num Horner step: add coefficient_3
    dw 632;
    dw 636;
    dw 68;  // Eval sumdlogdiv_b_num Horner step: add coefficient_2
    dw 640;
    dw 644;
    dw 64;  // Eval sumdlogdiv_b_num Horner step: add coefficient_1
    dw 648;
    dw 652;
    dw 60;  // Eval sumdlogdiv_b_num Horner step: add coefficient_0
    dw 656;
    dw 660;
    dw 112;  // Eval sumdlogdiv_b_den Horner step: add coefficient_7
    dw 664;
    dw 668;
    dw 108;  // Eval sumdlogdiv_b_den Horner step: add coefficient_6
    dw 672;
    dw 676;
    dw 104;  // Eval sumdlogdiv_b_den Horner step: add coefficient_5
    dw 680;
    dw 684;
    dw 100;  // Eval sumdlogdiv_b_den Horner step: add coefficient_4
    dw 688;
    dw 692;
    dw 96;  // Eval sumdlogdiv_b_den Horner step: add coefficient_3
    dw 696;
    dw 700;
    dw 92;  // Eval sumdlogdiv_b_den Horner step: add coefficient_2
    dw 704;
    dw 708;
    dw 88;  // Eval sumdlogdiv_b_den Horner step: add coefficient_1
    dw 712;
    dw 716;
    dw 84;  // Eval sumdlogdiv_b_den Horner step: add coefficient_0
    dw 720;
    dw 724;
    dw 620;  // None
    dw 732;
    dw 736;
    dw 744;  // None
    dw 748;
    dw 740;
    dw 120;  // None
    dw 752;
    dw 224;
    dw 756;  // None
    dw 264;
    dw 760;
    dw 760;  // None
    dw 764;
    dw 124;
    dw 124;  // None
    dw 768;
    dw 4;
    dw 760;  // None
    dw 772;
    dw 768;
    dw 784;  // None
    dw 796;
    dw 800;
    dw 4;  // None
    dw 800;
    dw 804;
    dw 128;  // None
    dw 808;
    dw 224;
    dw 812;  // None
    dw 264;
    dw 816;
    dw 816;  // None
    dw 820;
    dw 132;
    dw 132;  // None
    dw 824;
    dw 4;
    dw 816;  // None
    dw 828;
    dw 824;
    dw 840;  // None
    dw 852;
    dw 856;
    dw 804;  // None
    dw 856;
    dw 860;
    dw 200;  // None
    dw 864;
    dw 224;
    dw 868;  // None
    dw 264;
    dw 872;
    dw 204;  // None
    dw 876;
    dw 4;
    dw 872;  // None
    dw 880;
    dw 876;
    dw 860;  // None
    dw 884;
    dw 888;
    dw 120;  // None
    dw 892;
    dw 224;
    dw 896;  // None
    dw 264;
    dw 900;
    dw 900;  // None
    dw 904;
    dw 124;
    dw 124;  // None
    dw 908;
    dw 4;
    dw 900;  // None
    dw 912;
    dw 908;
    dw 924;  // None
    dw 936;
    dw 940;
    dw 4;  // None
    dw 940;
    dw 944;
    dw 128;  // None
    dw 948;
    dw 224;
    dw 952;  // None
    dw 264;
    dw 956;
    dw 956;  // None
    dw 960;
    dw 132;
    dw 132;  // None
    dw 964;
    dw 4;
    dw 956;  // None
    dw 968;
    dw 964;
    dw 980;  // None
    dw 992;
    dw 996;
    dw 944;  // None
    dw 996;
    dw 1000;
    dw 208;  // None
    dw 1004;
    dw 224;
    dw 1008;  // None
    dw 264;
    dw 1012;
    dw 212;  // None
    dw 1016;
    dw 4;
    dw 1012;  // None
    dw 1020;
    dw 1016;
    dw 1000;  // None
    dw 1024;
    dw 1028;
    dw 208;  // None
    dw 1032;
    dw 224;
    dw 1036;  // None
    dw 264;
    dw 1040;
    dw 1040;  // None
    dw 1044;
    dw 212;
    dw 212;  // None
    dw 1048;
    dw 4;
    dw 1040;  // None
    dw 1052;
    dw 1048;
    dw 8;  // None
    dw 1056;
    dw 4;
    dw 1072;  // None
    dw 1076;
    dw 1064;
    dw 216;  // None
    dw 1080;
    dw 224;
    dw 1084;  // None
    dw 264;
    dw 1088;
    dw 220;  // None
    dw 1092;
    dw 4;
    dw 1088;  // None
    dw 1096;
    dw 1092;
    dw 1076;  // None
    dw 1100;
    dw 1104;
    dw 1116;  // Sum of rhs_low * c0, rhs_high * c1, rhs_high_shifted * c2
    dw 1120;
    dw 1128;
    dw 1128;  // Sum of rhs_low * c0, rhs_high * c1, rhs_high_shifted * c2
    dw 1124;
    dw 1132;
    dw 4;  // Assert lhs - rhs = 0
    dw 1132;
    dw 748;

    mul_offsets_ptr_loc:
    dw 224;  // None
    dw 224;
    dw 240;
    dw 0;  // None
    dw 240;
    dw 244;
    dw 252;  // None
    dw 256;
    dw 248;
    dw 224;  // None
    dw 256;
    dw 260;
    dw 256;  // None
    dw 256;
    dw 268;
    dw 256;  // None
    dw 280;
    dw 284;
    dw 300;  // None
    dw 304;
    dw 296;
    dw 304;  // None
    dw 292;
    dw 308;
    dw 312;  // None
    dw 316;
    dw 320;
    dw 276;  // None
    dw 276;
    dw 324;
    dw 0;  // None
    dw 324;
    dw 328;
    dw 340;  // None
    dw 344;
    dw 320;
    dw 32;  // Eval sumdlogdiv_a_num Horner step: multiply by xA0
    dw 224;
    dw 356;
    dw 360;  // Eval sumdlogdiv_a_num Horner step: multiply by xA0
    dw 224;
    dw 364;
    dw 368;  // Eval sumdlogdiv_a_num Horner step: multiply by xA0
    dw 224;
    dw 372;
    dw 376;  // Eval sumdlogdiv_a_num Horner step: multiply by xA0
    dw 224;
    dw 380;
    dw 56;  // Eval sumdlogdiv_a_den Horner step: multiply by xA0
    dw 224;
    dw 388;
    dw 392;  // Eval sumdlogdiv_a_den Horner step: multiply by xA0
    dw 224;
    dw 396;
    dw 400;  // Eval sumdlogdiv_a_den Horner step: multiply by xA0
    dw 224;
    dw 404;
    dw 408;  // Eval sumdlogdiv_a_den Horner step: multiply by xA0
    dw 224;
    dw 412;
    dw 416;  // Eval sumdlogdiv_a_den Horner step: multiply by xA0
    dw 224;
    dw 420;
    dw 424;  // None
    dw 428;
    dw 384;
    dw 80;  // Eval sumdlogdiv_b_num Horner step: multiply by xA0
    dw 224;
    dw 432;
    dw 436;  // Eval sumdlogdiv_b_num Horner step: multiply by xA0
    dw 224;
    dw 440;
    dw 444;  // Eval sumdlogdiv_b_num Horner step: multiply by xA0
    dw 224;
    dw 448;
    dw 452;  // Eval sumdlogdiv_b_num Horner step: multiply by xA0
    dw 224;
    dw 456;
    dw 460;  // Eval sumdlogdiv_b_num Horner step: multiply by xA0
    dw 224;
    dw 464;
    dw 116;  // Eval sumdlogdiv_b_den Horner step: multiply by xA0
    dw 224;
    dw 472;
    dw 476;  // Eval sumdlogdiv_b_den Horner step: multiply by xA0
    dw 224;
    dw 480;
    dw 484;  // Eval sumdlogdiv_b_den Horner step: multiply by xA0
    dw 224;
    dw 488;
    dw 492;  // Eval sumdlogdiv_b_den Horner step: multiply by xA0
    dw 224;
    dw 496;
    dw 500;  // Eval sumdlogdiv_b_den Horner step: multiply by xA0
    dw 224;
    dw 504;
    dw 508;  // Eval sumdlogdiv_b_den Horner step: multiply by xA0
    dw 224;
    dw 512;
    dw 516;  // Eval sumdlogdiv_b_den Horner step: multiply by xA0
    dw 224;
    dw 520;
    dw 524;  // Eval sumdlogdiv_b_den Horner step: multiply by xA0
    dw 224;
    dw 528;
    dw 532;  // None
    dw 536;
    dw 468;
    dw 228;  // None
    dw 536;
    dw 540;
    dw 32;  // Eval sumdlogdiv_a_num Horner step: multiply by xA2
    dw 276;
    dw 548;
    dw 552;  // Eval sumdlogdiv_a_num Horner step: multiply by xA2
    dw 276;
    dw 556;
    dw 560;  // Eval sumdlogdiv_a_num Horner step: multiply by xA2
    dw 276;
    dw 564;
    dw 568;  // Eval sumdlogdiv_a_num Horner step: multiply by xA2
    dw 276;
    dw 572;
    dw 56;  // Eval sumdlogdiv_a_den Horner step: multiply by xA2
    dw 276;
    dw 580;
    dw 584;  // Eval sumdlogdiv_a_den Horner step: multiply by xA2
    dw 276;
    dw 588;
    dw 592;  // Eval sumdlogdiv_a_den Horner step: multiply by xA2
    dw 276;
    dw 596;
    dw 600;  // Eval sumdlogdiv_a_den Horner step: multiply by xA2
    dw 276;
    dw 604;
    dw 608;  // Eval sumdlogdiv_a_den Horner step: multiply by xA2
    dw 276;
    dw 612;
    dw 616;  // None
    dw 620;
    dw 576;
    dw 80;  // Eval sumdlogdiv_b_num Horner step: multiply by xA2
    dw 276;
    dw 624;
    dw 628;  // Eval sumdlogdiv_b_num Horner step: multiply by xA2
    dw 276;
    dw 632;
    dw 636;  // Eval sumdlogdiv_b_num Horner step: multiply by xA2
    dw 276;
    dw 640;
    dw 644;  // Eval sumdlogdiv_b_num Horner step: multiply by xA2
    dw 276;
    dw 648;
    dw 652;  // Eval sumdlogdiv_b_num Horner step: multiply by xA2
    dw 276;
    dw 656;
    dw 116;  // Eval sumdlogdiv_b_den Horner step: multiply by xA2
    dw 276;
    dw 664;
    dw 668;  // Eval sumdlogdiv_b_den Horner step: multiply by xA2
    dw 276;
    dw 672;
    dw 676;  // Eval sumdlogdiv_b_den Horner step: multiply by xA2
    dw 276;
    dw 680;
    dw 684;  // Eval sumdlogdiv_b_den Horner step: multiply by xA2
    dw 276;
    dw 688;
    dw 692;  // Eval sumdlogdiv_b_den Horner step: multiply by xA2
    dw 276;
    dw 696;
    dw 700;  // Eval sumdlogdiv_b_den Horner step: multiply by xA2
    dw 276;
    dw 704;
    dw 708;  // Eval sumdlogdiv_b_den Horner step: multiply by xA2
    dw 276;
    dw 712;
    dw 716;  // Eval sumdlogdiv_b_den Horner step: multiply by xA2
    dw 276;
    dw 720;
    dw 724;  // None
    dw 728;
    dw 660;
    dw 292;  // None
    dw 728;
    dw 732;
    dw 352;  // None
    dw 544;
    dw 740;
    dw 344;  // None
    dw 736;
    dw 744;
    dw 256;  // None
    dw 120;
    dw 756;
    dw 144;  // None
    dw 136;
    dw 776;
    dw 764;  // None
    dw 780;
    dw 752;
    dw 776;  // None
    dw 780;
    dw 784;
    dw 148;  // None
    dw 140;
    dw 788;
    dw 772;  // None
    dw 792;
    dw 752;
    dw 788;  // None
    dw 792;
    dw 796;
    dw 256;  // None
    dw 128;
    dw 812;
    dw 160;  // None
    dw 152;
    dw 832;
    dw 820;  // None
    dw 836;
    dw 808;
    dw 832;  // None
    dw 836;
    dw 840;
    dw 164;  // None
    dw 156;
    dw 844;
    dw 828;  // None
    dw 848;
    dw 808;
    dw 844;  // None
    dw 848;
    dw 852;
    dw 256;  // None
    dw 200;
    dw 868;
    dw 880;  // None
    dw 884;
    dw 864;
    dw 256;  // None
    dw 120;
    dw 896;
    dw 176;  // None
    dw 168;
    dw 916;
    dw 904;  // None
    dw 920;
    dw 892;
    dw 916;  // None
    dw 920;
    dw 924;
    dw 180;  // None
    dw 172;
    dw 928;
    dw 912;  // None
    dw 932;
    dw 892;
    dw 928;  // None
    dw 932;
    dw 936;
    dw 256;  // None
    dw 128;
    dw 952;
    dw 192;  // None
    dw 184;
    dw 972;
    dw 960;  // None
    dw 976;
    dw 948;
    dw 972;  // None
    dw 976;
    dw 980;
    dw 196;  // None
    dw 188;
    dw 984;
    dw 968;  // None
    dw 988;
    dw 948;
    dw 984;  // None
    dw 988;
    dw 992;
    dw 256;  // None
    dw 208;
    dw 1008;
    dw 1020;  // None
    dw 1024;
    dw 1004;
    dw 256;  // None
    dw 208;
    dw 1036;
    dw 1044;  // None
    dw 1060;
    dw 1032;
    dw 1056;  // None
    dw 1060;
    dw 1064;
    dw 1052;  // None
    dw 1068;
    dw 1032;
    dw 12;  // None
    dw 1068;
    dw 1072;
    dw 256;  // None
    dw 216;
    dw 1084;
    dw 1096;  // None
    dw 1100;
    dw 1080;
    dw 236;  // c1 = c0^2
    dw 236;
    dw 1108;
    dw 1108;  // c2 = c0^3
    dw 236;
    dw 1112;
    dw 888;  // rhs_low * c0
    dw 236;
    dw 1116;
    dw 1028;  // rhs_high * c1
    dw 1108;
    dw 1120;
    dw 1104;  // rhs_high_shifted * c2
    dw 1112;
    dw 1124;

    output_offsets_ptr_loc:
    dw 4;
}
