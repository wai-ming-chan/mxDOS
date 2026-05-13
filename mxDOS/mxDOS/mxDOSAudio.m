#import <AudioToolbox/AudioToolbox.h>
#include "mxDOSAudio.h"

AudioQueueRef gMxDOSAudioQueue = NULL;

volatile float mxDOSAudioVolume = 1.0f;

void mxDOS_setAudioVolume(float v) {
    float vol = (v < 0.0f) ? 0.0f : (v > 1.0f) ? 1.0f : v;
    mxDOSAudioVolume = vol;
    if (gMxDOSAudioQueue) {
        AudioQueueSetParameter(gMxDOSAudioQueue, kAudioQueueParam_Volume, vol);
    }
}
