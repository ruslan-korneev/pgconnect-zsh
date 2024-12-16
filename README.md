# PostgreSQL Connection Plugin for OhMyZsh
### Requirements
- [fzf](https://github.com/junegunn/fzf)
- [pglci](https://github.com/dbcli/pgcli)

### Installation
```zsh
git clone ... ${ZSH_CUSTOM}/plugins/.
```

- add this plugin to `.zshrc`
```.zshrc
plugins = (... pgconnect)
```

```zsh
source ~/.zshrc
```

### Usage

to add certain database you should use `~/.pg_service.conf`
example:
```.pg_service.conf
[db1]
host=0.0.0.0
port=5862
user=username
dbname=postgres

[db2]
host=0.0.0.0
port=5432
user=postgres
dbname=mysuperdatabase
```

right after that you gonna get those databases to the list
![](media/example.gif)

to hide a passwords you might use `.pgpass` or if u dont wanna hide it and have right inside a `.pg_service.conf` - go ahead with `password` attribute
