clean_worker:
	ansible-playbook -i scripts/ansible/hosts.yml scripts/ansible/playbooks/phase2.yaml  -e "rollback=true"
install_worker:
	ansible-playbook -i scripts/ansible/hosts.yml scripts/ansible/playbooks/phase2.yaml

clean_reinstall:
	ansible-playbook -i scripts/ansible/hosts.yml scripts/ansible/playbooks/phase2.yaml  -e "rollback=true"
	ansible-playbook -i scripts/ansible/hosts.yml scripts/ansible/playbooks/phase2.yaml


