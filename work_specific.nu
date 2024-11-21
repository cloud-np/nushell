# Git Clean (and the Locks)
def gc [] {
  rm -rf node_modules/@obg
  rm -rf node_modules/@sbb2b
  npm cache clear -f
  rm -rf .\dist\
  npm ci
  npm run postinstall
  npm run postinstall
}

# Git Clean (and the Locks)
def gcl [] {
  rm -rf node_modules/@obg
  rm -rf node_modules/@sbb2b
  rm -rf ./apps/adaptive/package-lock.json # b2c repo
  rm -rf ./package-lock.json # b2b repo
  npm cache clear -f
  rm -rf .\dist\
  npm i
  npm run postinstall
  npm run postinstall  # Sometimes for linking one its not enough (:
}

def ns [_brand: string = "f", _device: string = "d", --cenv: any = null] {
  let $brand = match $_brand {
    'f' => "firestorm_uiuplift",
    'n' => "nordicbet_uiuplift",
    'b' => "betsson_uiuplift",
    _ => "firestorm_uiuplift"
  }

  let device = match $_device {
    'd' => "desktop",
    'm' => "mobile",
    _ => "desktop"
  }

  # If env is set, update the proxy config file based on the input.
  if ($cenv != null) {
    # $env is used from nushell.
    let benv = match $cenv {
        't' => "test",
        'q' => "qa",
        'a' => "alpha",
        'p' => "",
        _ => "test"
    }

    let cf = $'($device)-cf.'
    let file = $'($env.PWD)\proxy-conf\($device)\($brand | str replace "_uiuplift" "").js'

    open $'($file)' | str replace --regex $'($cf)test\\.|qa\\.|alpha\\.|prod\\.' $'($cf)($benv).'
    # | save -f .\proxy-conf\desktop\firestorm.js
  }

  npm start $'($device)-($brand)' # npm start d-firestorm_uiuplift
}