# Completion for branches and remotes
export def git_branches_and_remotes [] {
  git_remotes
  | select name url
  | rename value description
  | append (
    git_local_branches | select name | rename value
  )
  | append (
    git_remote_branches | select name
    | rename value
  )
  | uniq
  | sort
}

# Git Commit no-verify
export def gcnv [message: string = "wip"] {
  git add .
  git commit -m $message --no-verify
}

export def glo [] {
  git log --oneline --graph --decorate --all
}

# Git Pull and Reset
export def gpr [--branch: string = "default"] {
  let target_branch = if ($branch == "default") {
    if (branch_exists "master") { "master" } else { "main" }
  } else {
    $branch
  }

  git pull origin $target_branch
  git reset --soft $'origin/($target_branch)'
  git restore --staged .
}

def branch_exists [branch: string] {
  git branch --list $branch
  | str trim
  | any { |line| $line == $branch }
}

export def git_comp_local_branches [] {
  git_local_branches
  | select name
  | rename value
  | uniq
  | sort
}

export def git_color_comp [] {
  [
    { value: "always", description: "Always respect color in output" },
    { value: "never", description: "Never use color" },
    { value: "auto", description: "Use colors if the output is a terminal" }
  ]
}

def commits_parse_line [line: string] {
  ( $line
  | split column "\u{0}"
  | rename ref author date subject
  | upsert date {|| $in | into datetime }
  )
}

export def git_commits [--hash-format: string = "%h", --max-count: int] {
  let args = [
    "log",
    $"--pretty=format:($hash_format)%x00%an%x00%aI%x00%s",
    $"--max-count=($max_count)",
  ]

  ( GIT_PAGER=cat run-external "git" ...$args
  | lines
  | each { |line| commits_parse_line $line }
  | flatten
  )
}

# Commits for completion
export def git_commits_comp [] {
  git_commits --max-count 500
  | insert description {||
      $"($in.subject) \(($in.author), ($in.date | date humanize)\)"
  }
  | select ref description
  | rename value description
}

export def ls_files_parse [line: string] {
  ( $line
  | split column "\u{0}"
  | rename name stage type size object_name
  )
}

export def git_files [] {
  let args = [
    "ls-files",
    "--format=%(path)%x00%(stage)%x00%(objecttype)%x00%(objectsize)%x00%(objectname)",
  ]

  ( GIT_PAGER=cat run-external "git" ...$args
  | lines
  | each {|line| ls_files_parse $line }
  | flatten
  )

}

def for_each_ref [filter] {
  run-external "git" "for-each-ref" "--format=%(refname:lstrip=2)%00%(objectname)" $filter
  | lines
}

# Local branches and commits
export def git_local_branches [] {
  for_each_ref "refs/heads/"
  | parse "{name}\u{00}{commit}"
}

# Remotes for the current repository
export def git_remotes [] {
  run-external "git" "remote" "-v"
  | lines
  | parse "{name}\t{url} ({type})"
}

# Local branches and commits
export def git_remote_branches [] {
  for_each_ref "refs/remotes/"
  | lines
  | parse "{remote}/{name}\u{00}{commit}"
  | move remote --after name
}

# This one broke everything
def record_match [input, matchers: record] {
    ( echo $matchers
    | get $input
    | do $in
    )
}

# Parses most of `git status --porcelain=2`
#
# This does not parse the `<sub>` field containing the submodule status
#
# This does not parse the `<X><score>` field containing the rename/copy similarity status
def parse_line [line: string] {
  let line = ( $line | split row " " )
  let status = $line.0

  # TODO: This panics the main thread lol.
  # Check why and how to fix it.
  record_match $status {
    "?": {
      ( {}
      | insert name $line.1
      | insert status "untracked"
      | insert staged "untracked"
      | insert unstaged "untracked"
      )
    },
    "!": {
      ( {}
      | insert name $line.1
      | insert status "ignored"
      | insert staged "untracked"
      | insert unstaged "untracked"
      )
    },
    "1": {
      let states = parse_states $line.1

      ( {}
      | insert name $line.8
      | insert status "changed"
      | insert staged $states.staged
      | insert unstaged $states.unstaged
      | insert mode_head $line.3
      | insert mode_index $line.4
      | insert mode_worktree $line.5
      | insert name_head $line.6
      | insert name_index $line.7
      )
    },
    "2": {
      let paths = parse_rename_path $line.9
      let states = parse_states $line.1

      ( {}
      | insert status "renamed"
      | insert name $paths.0
      | insert staged $states.staged
      | insert unstaged $states.unstaged
      | insert mode_head $line.3
      | insert mode_index $line.4
      | insert mode_worktree $line.5
      | insert name_head $line.6
      | insert name_index $line.7
      | insert original_name $paths.1
      )
    },
    "u": {
      let states = parse_states $line.1

      ( {}
      | insert status "unmerged"
      | insert name $line.10
      | insert staged $states.staged
      | insert unstaged $states.unstaged
      | insert mode_stage_1 $line.3
      | insert mode_stage_2 $line.4
      | insert mode_stage_3 $line.5
      | insert mode_worktree $line.6
      | insert name_stage_1 $line.7
      | insert name_stage_2 $line.8
      | insert name_stage_3 $line.9
      )
    }
  }
}

# Paths for a rename record are separated by a tab character
def parse_rename_path [paths: string] {
  ( $paths
  | split row "\t" )
}

# State marker
def parse_state [state: string] {
  match $state {
    "." => { "unmodified" },
    "M" => { "modified" },
    "T" => { "type changed" },
    "A" => { "added" },
    "D" => { "deleted" },
    "R" => { "renamed" },
    "C" => { "copied" },
    "U" => { "updated" }
  }
}

# States field contains the staged and unstaged status of an object
def parse_states [states: string] {
  let states = ( $states | split chars )

  let staged = parse_state $states.0
  let unstaged = parse_state $states.1

  { staged: $staged, unstaged: $unstaged }
}

# export def git_status [ignored: bool] {
#   let args = ["status", "--porcelain=2"]
#   let args = if ($ignored | into bool) {
#     ($args | append "--ignored")
#   } else {
#     $args
#   }

#   ( run-external "git" ...$args
#   | lines
#   | each { |line| parse_line $line }
#   )
# }

def stash_list_parse_line [line: string] {
  ( $line
  | split column "\u{0}"
  | rename date subject
  | update subject { |r|
    $r.subject
    | parse -r "WIP on (?P<branch>.*?): (?P<commit>\\w+) (?P<subject>.*)"
  }
  | flatten -a
  )
}

export def stash_list [] {
  let args = [
    "reflog",
    "stash"
    "--pretty=format:%aI%x00%s",
  ]

  ( GIT_PAGER=cat run-external "git" ...$args
  | lines
  | par-each { |line| stash_list_parse_line $line }
  | flatten
  )
}

def submodule_status_parse_line [line: string] {
  ( $line
  | parse -r '(?P<status>[ U+-])(?P<SHA>[^ ]+) (?P<path>.*?) \((?P<ref>.*)\)'
  | move status --after ref
  | move path --before SHA
  | move ref --before SHA
  )
}

export def submodule_status [recursive: bool] {
  let args = [
    "submodule",
    "status"
  ]

  let args = if $recursive {
    $args | append "--recursive"
  } else {
    $args
  }

  # TODO: Read .gitmodules and run git -C $submodule rev-parse HEAD to find
  # commits and be recursive
  ( GIT_PAGER=cat run-external "git" ...$args
  | lines
  | par-each { |line| submodule_status_parse_line $line }
  | flatten
  )
}

export def git_tags [] {
  let args = [
    "tag",
    "--list"
    "--format"
    "%(refname:strip=2)%00%(contents:subject)"
  ]

  GIT_PAGER=cat run-external "git" ...$args
  | lines
  | each {||
    $in
    | split column "\u{0}"
  }
  | flatten
  | rename tag subject
}

# Git Log
def gl [
  --n: int = 10 # n lines to log
] {
  # Without date manipulation
  # git log --pretty=%h»¦«%s»¦«%aN»¦«%aE»¦«%aD -n $nn | lines | split column "»¦«" hash commit-message author email date
  git log --pretty=%h»¦«%s»¦«%aN»¦«%aE»¦«%aD -n $n | lines | split column "»¦«" hash commit-message author email date | upsert date {|d| $d.date | into datetime} | sort-by date | reverse
}
