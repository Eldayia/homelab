FROM ghcr.io/wg-easy/wg-easy:15.2.2

# Raspberry Pi OS 6.18 utilise nftables et ne fournit plus les
# modules ip_tables/iptable_nat du backend historique.
RUN update-alternatives \
      --install /usr/sbin/iptables iptables /usr/sbin/iptables-nft 20 \
      --slave /usr/sbin/iptables-restore iptables-restore /usr/sbin/iptables-nft-restore \
      --slave /usr/sbin/iptables-save iptables-save /usr/sbin/iptables-nft-save \
 && update-alternatives \
      --install /usr/sbin/ip6tables ip6tables /usr/sbin/ip6tables-nft 20 \
      --slave /usr/sbin/ip6tables-restore ip6tables-restore /usr/sbin/ip6tables-nft-restore \
      --slave /usr/sbin/ip6tables-save ip6tables-save /usr/sbin/ip6tables-nft-save
