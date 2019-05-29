
#define multBy4(x)  ((x) << 2)
#define multBy16(x) ((x) << 4)

KW_GLOBAL_KERNEL void kernelPartialsPartialsEdgeFirstDerivatives(KW_GLOBAL_VAR REAL* KW_RESTRICT out,
                                                                 KW_GLOBAL_VAR REAL* KW_RESTRICT partials0,
                                                                 KW_GLOBAL_VAR REAL* KW_RESTRICT matrices0,
                                                                 KW_GLOBAL_VAR unsigned int* KW_RESTRICT offsets,
                                                                 KW_GLOBAL_VAR REAL* KW_RESTRICT weights,
                                                                 int totalPatterns, int categoryCount) {
#ifdef FW_OPENCL_CPU // CPU/MIC implementation
    // Not implemented
#else // GPU implementation

    int tx = KW_LOCAL_ID_0;
    int state = tx & 0x3;
    int pat = tx >> 2;
    int patIdx = KW_LOCAL_ID_1;
    int pattern = __umul24(KW_GROUP_ID_0, PATTERN_BLOCK_SIZE * 4) + multBy4(patIdx) + pat;
    int y = multBy16(KW_GROUP_ID_0 * PATTERN_BLOCK_SIZE + patIdx);

    int node = KW_GROUP_ID_1;
    int instructionOffset = node * 3;

    unsigned int partials1Offset = offsets[instructionOffset + 0];
    unsigned int partials2Offset = offsets[instructionOffset + 1];
    unsigned int matrices1Offset = offsets[instructionOffset + 2];

    KW_LOCAL_MEM REAL sMatrix2[16];

    KW_LOCAL_MEM REAL sPartials1[PATTERN_BLOCK_SIZE * 4 * 4];
    KW_LOCAL_MEM REAL sPartials2[PATTERN_BLOCK_SIZE * 4 * 4];

    /* TODO: Currently assumes MATRIX_BLOCK_SIZE >> matrixCount */\
    KW_LOCAL_MEM REAL sWeights[MATRIX_BLOCK_SIZE];

    for (int c = 0; c < categoryCount; c += KW_LOCAL_SIZE_0) {
        int x = c + KW_LOCAL_ID_0;
        if (x < categoryCount) {
            sWeights[x] = weights[x];
        }
    }

    KW_LOCAL_FENCE;

    REAL numerator = 0;
    REAL denominator = 0;

    REAL lPartial1;
    REAL lPartial2;

    for (int c = 0; c < categoryCount; ++c) {

        KW_GLOBAL_VAR REAL* KW_RESTRICT partials1 = partials0 + partials1Offset + totalPatterns * PADDED_STATE_COUNT * c;
        KW_GLOBAL_VAR REAL* KW_RESTRICT partials2 = partials0 + partials2Offset + totalPatterns * PADDED_STATE_COUNT * c;
        KW_GLOBAL_VAR REAL* KW_RESTRICT matrix2 = matrices0 + matrices1Offset + PADDED_STATE_COUNT * PADDED_STATE_COUNT * c;

        /* copy PADDED_STATE_COUNT * PATTERN_BLOCK_SIZE length partials*/
        if (pattern < totalPatterns) {
            lPartial1 = partials1[y | tx]; /*All coalesced memory*/
            sPartials2[multBy16(patIdx) | tx] = lPartial2 = partials2[y | tx];
        } else {
            lPartial1 = 0;
            sPartials2[multBy16(patIdx) | tx] = lPartial2 = 0;
        }

        FMA(lPartial1, lPartial2 * sWeights[c], denominator);

        if (patIdx == 0 ) {
            sMatrix2[tx] = matrix2[tx];
        }

        KW_LOCAL_FENCE;

        REAL sum2;
        int i = pat;
        int patIdx16pat4 = multBy16(patIdx) | (tx & 0xC);

        sum2 = sMatrix2[multBy4(i) | state] * sPartials2[patIdx16pat4 | i];
        i = (i + 1) & 0x3;
        FMA(   sMatrix2[multBy4(i) | state],  sPartials2[patIdx16pat4 | i], sum2);
        i = (i + 1) & 0x3;
        FMA(   sMatrix2[multBy4(i) | state],  sPartials2[patIdx16pat4 | i], sum2);
        i = (i + 1) & 0x3;
        FMA(   sMatrix2[multBy4(i) | state],  sPartials2[patIdx16pat4 | i], sum2);

        KW_LOCAL_FENCE; // TODO Is this necessary?

        FMA(lPartial1, sum2 * sWeights[c], numerator);

//        partials1 += totalPatterns * PADDED_STATE_COUNT;
//        partials2 += totalPatterns * PADDED_STATE_COUNT;
    }

    sPartials1[patIdx * PATTERN_BLOCK_SIZE + tx] = numerator;
    sPartials2[patIdx * PATTERN_BLOCK_SIZE + tx] = denominator;

    KW_LOCAL_FENCE;

    if (state < 2) {
        sPartials1[patIdx * PATTERN_BLOCK_SIZE + tx] += sPartials1[patIdx * PATTERN_BLOCK_SIZE + tx + 2];
        sPartials2[patIdx * PATTERN_BLOCK_SIZE + tx] += sPartials2[patIdx * PATTERN_BLOCK_SIZE + tx + 2];
    }

    KW_LOCAL_FENCE;

    if (state < 1) {
        sPartials1[patIdx * PATTERN_BLOCK_SIZE + tx] += sPartials1[patIdx * PATTERN_BLOCK_SIZE + tx + 1];
        sPartials2[patIdx * PATTERN_BLOCK_SIZE + tx] += sPartials2[patIdx * PATTERN_BLOCK_SIZE + tx + 1];
    }

    KW_LOCAL_FENCE;

    if (pattern < totalPatterns) {
        if (state == 0) {
            // TODO Transpose results and do coalesced write
            out[totalPatterns * node + pattern] =
                    sPartials1[patIdx * PATTERN_BLOCK_SIZE + multBy4(pat) + 0] /
                    sPartials2[patIdx * PATTERN_BLOCK_SIZE + multBy4(pat) + 0]; // pre;
//            out[totalPatterns * node + pattern] = sPartials1[patIdx][0];  // Write numerator
//            out[totalPatterns * (KW_NUM_GROUPS_1 + node) + pattern] = sPartials2[patIdx][0]; // Write denominator
        }
    }
#endif
}
