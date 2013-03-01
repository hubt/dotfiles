<?xml version="1.0"?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:output method="xml"
    doctype-system="http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd"
    doctype-public="-//W3C//DTD XHTML 1.0 Transitional//EN" />
  <xsl:template match="/">
    
<html>
<head>
  <title><xsl:value-of select="//title"/></title>
  <style type="text/css">
  h3 { font-variant: small-caps;}  
  h2 { font-variant: small-caps;}  
  strong { font-family: Times, serif}
  P { text-align: justify ; }

  </style>
</head>
<body>
<table width="100%" border="0">
  <tbody>
    <tr>
      <td width="33%">
        <xsl:if test="//mapurl">
          <a>
            <xsl:attribute name="href">
              <xsl:value-of select="//mapurl" />
            </xsl:attribute>
          <strong>Home Address:</strong> 
          </a>
        </xsl:if>
        <xsl:if test="not(//mapurl)">
          <strong>Home Address:</strong> 
        </xsl:if>
       </td>
      <td width="33%" rowspan="2">
      <h2 align="center"><xsl:value-of select="//name"/></h2>
      </td>
      <td width="33%" align="right"><strong>Net Address:</strong> </td>
    </tr>
    <tr>
      <td><xsl:value-of select="//address1" /><br/>
          <xsl:value-of select="//address2" /><br/>
          <xsl:value-of select="//phone" /><br/>
      </td>
      <td align="right"> 
      <a><xsl:attribute name="href">
                                mailto:<xsl:value-of select="//email" />
                             </xsl:attribute >
         <xsl:value-of select="//email" /></a><br/>
      <a href="http://www.chen.net/%7Ehubt/resume/">http://www.chen.net/~hubt/resume/</a> </td>
    </tr>
  </tbody>
</table>
<hr/>
<table cellspacing="4" cellpadding="5" align="left" width="100%">
  <tbody>
    <xsl:if test="//objective">
    <tr>
      <td bgcolor="#bbbbbb" valign="top">
      <h3>Objective: </h3>
      </td>
      <td>
      <p> <xsl:value-of select="//objective" /></p>
      </td>
    </tr>
    </xsl:if>
    <tr>
      <td bgcolor="#bbbbbb" valign="top">
      <h3>Skills:</h3>
      </td>
      <td>
      <table border="0" cellpadding="1" cellspacing="10">
        <tbody>
          <tr>
            <xsl:for-each select="//skills/category" >
            <th align="left"><xsl:value-of select="@name" /></th>
            </xsl:for-each>
          </tr>
        </tbody><tbody>
            <tr>
            <xsl:for-each select="//skills/category" >
              <td valign="top">
                  <xsl:variable name="skillCategory" select="." />
                  <table><tbody>
                    <xsl:for-each select="item" >
                      <tr>
                      <td height="15" align="left">
                        <xsl:value-of select="." />
                      </td>
                      </tr>
                    </xsl:for-each>
                  </tbody></table>
              </td>
            </xsl:for-each>
            </tr>
        </tbody>
      </table>
      </td>
    </tr>
    <tr>
      <td bgcolor="#bbbbbb" valign="top">
      <h3>Experience:</h3>
      </td>
      <td>
      <ul>
        <xsl:for-each select="//experience" >
        <li><strong> <xsl:value-of select="title" />: </strong>
          <xsl:choose>
            <xsl:when test="url">
              <a><xsl:attribute name="href">
                   <xsl:value-of select="url" />
                 </xsl:attribute>
                 <strong><xsl:value-of select="company/name" /></strong>
              </a> 
            </xsl:when>
            <xsl:otherwise>
                 <strong><xsl:value-of select="company/name" /></strong>
            </xsl:otherwise>
          </xsl:choose>
             <xsl:value-of select="company/description" />
          &#160; <xsl:value-of select="date" /> 
          <p> 
          <xsl:value-of select="description" />
          </p>
        </li>
        </xsl:for-each>
      </ul>
      </td>
    </tr>
    <xsl:if test="//education">
    <tr>
      <td bgcolor="#bbbbbb" valign="top">
      <h3>Education: </h3>
      </td>
      <td>
      <ul>
        <xsl:for-each select="//education/school" >
        <li><strong>
          <xsl:value-of select="type" />: 
            </strong> 
            <a>
               <xsl:attribute name="href">
                 <xsl:value-of select="url" />
               </xsl:attribute>
               <xsl:value-of select="name" /> 
            </a>&#160; 
               <xsl:if test="location" > 
               <xsl:value-of select="location" /> 
               </xsl:if>
            <br/> 
          <strong>Concentration: </strong>
               <xsl:value-of select="degree" /> in
               <xsl:value-of select="major" />,
               <xsl:value-of select="graduation" />
            <br/>
          <xsl:if test="gpa">
          <strong>GPA: </strong>
                 <xsl:value-of select="gpa" />
          </xsl:if>
        </li>
        </xsl:for-each>
      </ul>
      </td>
    </tr>
    </xsl:if>
  </tbody>
</table>
</body>
</html>
  </xsl:template>
</xsl:stylesheet>
