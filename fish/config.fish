source /usr/share/cachyos-fish-config/cachyos-config.fish

# overwrite greeting — disable the fastfetch run on every new terminal
# (cachyos-config.fish defines fish_greeting to call fastfetch; this empties it)
function fish_greeting
end
