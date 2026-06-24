pkgname=lsh
pkgver=1.0
pkgrel=2
pkgdesc="Lightweight System Shell written in Ruby"
arch=('any')
url="https://github.com/xkikiyaa/lsh"
license=('GPL')
depends=('ruby')
source=('lsh.rb' 'lsh.install')
sha256sums=('SKIP' 'SKIP')
install=lsh.install

package() {
install -Dm755 "$srcdir/lsh.rb" "$pkgdir/usr/bin/lsh"
}
