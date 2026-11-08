TRUNCATE TABLE addressbook;
LOAD DATA LOCAL INFILE 'D:\\OneDrive\\Label Pro Analysis\\Database\\csv-output\\AddressBook.csv'
INTO TABLE addressbook
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(rec_no,addressbookid,name,sallutation,searchname,physicaladdress1,physicaladdress2,physicaladdress3,physicaladdress4,physicaladdress5,postaladdress1,postaladdress2,postaladdress3,postaladdress4,postaladdress5,telephone,extentiondirectline,fax,email,voip,mobile,pager,webaddress,userdescr1,userdetail1,userdescr2,userdetail2,inactive,inactiveby,inactivedate,blocked,blockedby,blockeddate,registrationnumber,taxnumber,externalreference,prospect,customer,brokeragent,supplier,employee,cashclient,locationid,debtorsinterfaceaccounnumber,creditlimit,estlayout,jtlayout,invlayout,dnlayout,blockdn,blockdnuser,blockdndate,suppliercategory,palladiumpartnumber,contractpricing,dealerpricing,enduserpricing,taxtype,nobrandingonpacking,createdate,createtime,createuser,quoteinforeigncurrency,sparestr1,sparestr2,sparenum1,sparenum2);
SELECT ROW_COUNT() AS loaded_rows;
SHOW COUNT(*) WARNINGS;
SHOW WARNINGS LIMIT 20;
