# Cybex OS 1.0.6

- Dell XPS 14 and XPS 16: the speakers no longer go silent. The camera's driver took a line the speaker amplifiers need at startup, so no sound card appeared.
- Dell XPS 13 (2026): supported. New installations get display settings against stutter and late frames, and working speakers on the Panther Lake model, with less bass until a newer Linux kernel.
- HP ZBook Ultra G1a: supported. New installations stop a power-management error that repeated every second after sleep.
- Dell XPS: the SSD gets its memory buffer back, so drives without their own cache keep their speed.
- Laptops: the microphone mute light follows the microphone, however it was muted.
- Wi-Fi 6E and 7: the wireless regulatory database is installed, so 6 GHz networks can be used.
- System check: a new Laptop entry reports known problems of these laptops, such as Pluton turned off on the ZBook, which stops it waking from sleep. An XPS 13 or ZBook installed before this release is told the one line that turns its support on.
- Dell XPS laptops restart once to apply this update; other computers install it without a restart (coming from 1.0.3 or earlier, once).
