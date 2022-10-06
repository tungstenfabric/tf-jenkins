project_id=$(openstack project show admin -c id -f value)
openstack quota set --instances 9999 $project_id
openstack quota set --cores 1024 $project_id
openstack quota set --ram 10000000 $project_id
openstack quota set  --volumes 10000 $project_id
openstack quota set --gigabytes 10000 $project_id

#After adding ceph OSDs
openstack quota set  --volumes 20000 $project_id
openstack quota set --gigabytes 20000 $project_id

