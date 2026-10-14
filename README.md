# neovim-config

## Instalacja

```sh
git clone git@github.com:realpiekar/neovim-config.git ~/.config/nvim
brew bundle --file ~/.config/nvim/Brewfile
nvim
```

## Aktualizacja

```sh
cd ~/.config/nvim && git pull
```

- `:Lazy restore`, gdy zmieniły się wersje wtyczek w `lazy-lock.json`,
- `brew bundle --file ~/.config/nvim/Brewfile`, gdy w `Brewfile` doszło nowe narzędzie.
