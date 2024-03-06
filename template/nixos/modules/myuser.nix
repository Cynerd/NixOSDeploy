{...}: {
  users = {
    groups.john.gid = 1000;
    users.john = {
      uid = 1000;
      subUidRanges = [
        {
          count = 65534;
          startUid = 10000;
        }
      ];
      group = "john";
      extraGroups = ["users" "wheel" "dialout" "kvm" "uucp" "wireshark"];
      subGidRanges = [
        {
          count = 65534;
          startGid = 10000;
        }
      ];
      isNormalUser = true;
      createHome = true;
      hashedPasswordFile = "/run/secrets/john.pass";
      openssh.authorizedKeys.keyFiles = ["/run/secrets/john.pub"];
    };
  };
}
