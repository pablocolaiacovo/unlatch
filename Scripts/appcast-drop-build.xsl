<?xml version="1.0" encoding="UTF-8"?>
<!--
  Removes every <item> whose sparkle:version (element or enclosure attribute)
  equals the "build" parameter, and copies everything else unchanged.

  Why: a stable tag on the same commit as its last beta has the same
  CFBundleVersion. generate_appcast matches items by version and would update
  the beta item in place, keeping its beta channel tag and notes, so stable
  users would never be offered the release. Dropping the old item first makes
  generate_appcast write a fresh one. See Design/sparkle-updates.md, 2.6.

  Usage: xsltproc with the string parameter "build" set to the build number,
  this stylesheet, and the current appcast.xml.

  XSLT 1.0 does not allow variables in match patterns, hence xsl:if inside
  the item template. cdata-section-elements keeps embedded notes in CDATA.
-->
<xsl:stylesheet version="1.0"
    xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
    xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <xsl:output method="xml" encoding="UTF-8" indent="yes" cdata-section-elements="description"/>
  <xsl:param name="build" select="''"/>

  <xsl:template match="@*|node()">
    <xsl:copy>
      <xsl:apply-templates select="@*|node()"/>
    </xsl:copy>
  </xsl:template>

  <xsl:template match="item">
    <xsl:if test="not(sparkle:version = $build) and not(enclosure/@sparkle:version = $build)">
      <xsl:copy>
        <xsl:apply-templates select="@*|node()"/>
      </xsl:copy>
    </xsl:if>
  </xsl:template>
</xsl:stylesheet>
