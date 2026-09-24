# SparkLang schedule-ref — systemd user timer templates.

Install the `.timer` + `.service` under `~/.config/systemd/user/`,
edit `WorkingDirectory` / paths to your checkout, then:

```bash
systemctl --user daemon-reload
systemctl --user enable --now spark-voice-loop-nightly.timer
```

Dry path (no timer):

```bash
./spark-voice-loop --stmt-file examples/voice_loop/schedule.spark
```

CPU only. No telephony. Synthetic fixtures.
