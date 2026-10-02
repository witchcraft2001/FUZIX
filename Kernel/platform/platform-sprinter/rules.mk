CROSS_CCOPTS += --external-banker
#
export BANKED=-banked

export CROSS_CC_SEG1=--codeseg CODE1
export CROSS_CC_SEG2=--codeseg CODE2
export CROSS_CC_SEG3=--codeseg CODE2
export CROSS_CC_SEG4=--codeseg CODE3
export CROSS_CC_VIDEO=--codeseg VIDEO
export CROSS_CC_FONT=--constseg FONT
#
export CROSS_CC_SYS1=--codeseg CODE1
export CROSS_CC_SYS2=--codeseg CODE1
export CROSS_CC_SYS3=--codeseg CODE1
export CROSS_CC_SYS4=--codeseg CODE1
export CROSS_CC_SYS5=--codeseg CODE3
export CROSS_CC_SEGDISC=--codeseg DISCARD --constseg DISCARD
export CROSS_CC_NETWORK=--codeseg CODE2

# Keep the WIN3 exec limit local to Sprinter while retaining bank16k setup.
mm/bank16k.rel: CROSS_CCOPTS += -Dpagemap_prepare=spr_prep_old
mm/bank16k.rel: mm/bank16k.c platform/platform-sprinter/rules.mk
