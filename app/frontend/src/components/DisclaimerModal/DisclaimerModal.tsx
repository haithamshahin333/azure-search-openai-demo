import { useTranslation } from 'react-i18next';
import { Button } from '@fluentui/react-components';
import { Settings24Regular } from '@fluentui/react-icons';
import { Modal, IconButton, getTheme, mergeStyleSets, Stack, Text } from '@fluentui/react';

const theme = getTheme();
const contentStyles = mergeStyleSets({
    container: {
        display: 'flex',
        flexDirection: 'column',
        padding: '20px',
        backgroundColor: theme.palette.white,
        boxShadow: theme.effects.elevation8,
        borderRadius: '4px',
    },
    header: {
        display: 'flex',
        justifyContent: 'space-between',
        alignItems: 'center',
        marginBottom: '15px',
        borderBottom: `1px solid ${theme.palette.neutralLight}`,
        paddingBottom: '10px',
    },
    body: {
        marginBottom: '20px',
    },
    footer: {
        display: 'flex',
        justifyContent: 'flex-end',
        borderTop: `1px solid ${theme.palette.neutralLight}`,
        paddingTop: '10px',
    },
});

interface Props {
    show: boolean;
    onClose: () => void;
}

export const DisclaimerModal = ({ show, onClose }: Props) => {
    const { t } = useTranslation();

    if (!show) {
        return null;
    }

    return (
        <Modal
            isOpen={show}
            onDismiss={onClose}
            isBlocking={false}
            containerClassName={contentStyles.container}
        >
            <Stack>
                <div className={contentStyles.header}>
                    <Text variant="large">Disclaimer</Text>
                    <IconButton
                        iconProps={{ iconName: 'Cancel' }}
                        onClick={onClose}
                    />
                </div>
                <div className={contentStyles.body}>
                    <Text>{t("disclaimer")}</Text>
                </div>
            </Stack>
        </Modal>
    );
};
