Video fixtures for the embedded-file tests, made once with ffmpeg (software H.264, not the hardware encoder). No test encodes video as it runs.

    ffmpeg -f lavfi -i "testsrc=size=64x64:rate=10:duration=1" -c:v libx264 -pix_fmt yuv420p -movflags +faststart Clip.mov
    ffmpeg -f lavfi -i "testsrc=size=64x64:rate=10:duration=5" -c:v libx264 -pix_fmt yuv420p -g 10 \
      -movflags frag_keyframe+empty_moov+default_base_moof+skip_trailer -f mov Fragmented.mov
