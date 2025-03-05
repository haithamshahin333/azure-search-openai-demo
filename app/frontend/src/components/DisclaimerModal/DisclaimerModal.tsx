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
        whiteSpace: 'normal', // Add this line
        wordWrap: 'break-word', // Add this line
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
        whiteSpace: 'normal', // Add this line
        wordWrap: 'break-word', // Add this line
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
                <div className={contentStyles.body}>
                    <Text variant="small">{t("sub_disclaimer")}</Text>
                </div>
            </Stack>
        </Modal>
    );
};
