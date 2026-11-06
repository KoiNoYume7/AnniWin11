@{
    # =======================================================================
    #  debloat.psd1  --  appx packages to REMOVE
    #
    #  SAFETY: nothing here is removed implicitly. Only names you list below
    #  are touched. Each is removed for the current user AND deprovisioned so
    #  it does not come back for new accounts. Every removal is logged.
    #
    #  Match by package Name (not full PackageFullName). Wildcards allowed.
    #  Preview what is installed with:
    #     Get-AppxPackage | Select-Object Name | Sort-Object Name
    #
    #  tiny11 is already slim, so this list is empty by default. We will
    #  enumerate leftovers on the actual machine and add them after review.
    # =======================================================================

    Remove = @(
        # 'Microsoft.MicrosoftSolitaireCollection'
        # 'Microsoft.BingNews'
        # 'Microsoft.BingWeather'
        # 'Clipchamp.Clipchamp'
    )
}
